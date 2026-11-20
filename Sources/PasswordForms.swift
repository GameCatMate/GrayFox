import Foundation
import WebKit

@MainActor
final class PasswordForms: NSObject, WKScriptMessageHandlerWithReply {
    static let autofillKey = "password-autofill"
    private static let world = WKContentWorld.world(name: "myBro.PasswordForms")
    private weak var browser: Browser?

    init(browser: Browser) {
        self.browser = browser
    }

    static func install(in controller: WKUserContentController, for browser: Browser) {
        controller.addScriptMessageHandler(PasswordForms(browser: browser), contentWorld: world, name: "myBroPasswords")
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: true, in: world))
    }

    static func refresh(in web: WKWebView) {
        web.evaluateJavaScript("globalThis.__myBroScanPasswords?.()", in: nil, in: world, completionHandler: nil)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        let frame = message.frameInfo
        let securityOrigin = frame.securityOrigin
        let port = securityOrigin.port == 0 ? 443 : securityOrigin.port
        guard let browser, !browser.isPrivate, let web = message.webView, browser.active?.view === web,
              frame.isMainFrame, securityOrigin.protocol == "https",
              let url = frame.request.url, let origin = WebsiteOrigin(url),
              origin.url.host?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased() ==
                securityOrigin.host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased(),
              (origin.url.port ?? 443) == port,
              web.url.flatMap(WebsiteOrigin.init) == origin,
              let body = message.body as? [String: String], let operation = body["operation"],
              let username = body["username"], username.utf8.count <= 1024 else {
            replyHandler(NSNull(), nil)
            return
        }

        switch operation {
        case "accounts", "fill":
            guard browser.passwordAutofill else { replyHandler(NSNull(), nil); return }
            do {
                let entries = try browser.passwordVault.entries().filter { $0.origin == origin }
                if operation == "accounts" {
                    replyHandler(Array(Set(entries.map(\.username))).sorted(), nil)
                    return
                }
                let entry = body["chosen"] == "true"
                    ? entries.first { $0.username == username }
                    : SavedLogin.matching(in: entries, origin: origin, username: username)
                if let entry {
                    replyHandler(["username": entry.username, "password": entry.password], nil)
                } else {
                    replyHandler(NSNull(), nil)
                }
            } catch {
                browser.passwordError = error.localizedDescription
                replyHandler(NSNull(), nil)
            }
        case "save":
            if let password = body["password"] {
                let entry = SavedLogin(origin: origin, username: username, password: password)
                if entry.isValid, let entries = try? browser.passwordVault.entries(),
                   !entries.contains(entry), browser.pendingLogin != entry {
                    browser.pendingLogin = entry
                }
            }
            replyHandler(NSNull(), nil)
        default:
            replyHandler(NSNull(), nil)
        }
    }

    static let script = #"""
    (() => {
      if (location.protocol !== "https:" || window.top !== window) return;
      const bridge = webkit.messageHandlers.myBroPasswords;
      let attempts = new WeakMap(), accountRequest, chosenUser;
      const pending = new WeakSet();
      let popup, popupOwner, focusMenu;
      let timer;

      function safe(root, submitter) {
        if (!root?.isConnected) return false;
        const form = root instanceof HTMLFormElement ? root : null;
        try {
          const action = submitter?.getAttribute("formaction") ?? form?.action ?? location.href;
          const overrides = form ? [...form.elements] : [...root.querySelectorAll("[formaction]")];
          return new URL(action, location.href).origin === location.origin &&
            !overrides.some(button => button.hasAttribute("formaction") &&
              new URL(button.getAttribute("formaction"), location.href).origin !== location.origin);
        } catch { return false; }
      }

      const visible = input => input instanceof HTMLInputElement && !input.matches(":disabled") &&
          input.getClientRects().length > 0 &&
          !["hidden", "collapse"].includes(getComputedStyle(input).visibility) &&
          (typeof input.checkVisibility !== "function" || input.checkVisibility({checkOpacity: true}));
      const userField = input => (["text", "email", "tel"].includes(input.type) ||
        input.type === "hidden" && input.autocomplete.includes("username")) &&
        !/one-time-code|new-password/.test(input.autocomplete) &&
        !/search|captcha|verification|otp/i.test(input.name + " " + input.id);
      const namedUser = input => /username|email/.test(input.autocomplete) ||
        /^(user(name)?|login|email|identifier)$/i.test(input.name || input.id) || input.type === "email";

      function container(input) {
        if (input.form) return input.form;
        for (let root = input.parentElement; root; root = root.parentElement) {
          if (root === document.body || [...root.querySelectorAll("input")].some(i => i !== input && visible(i) && userField(i))) return root;
        }
      }

      function fields(root, submitter) {
        if (!safe(root, submitter)) return;
        const inputs = [...(root instanceof HTMLFormElement ? root.elements : root.querySelectorAll("input"))];
        const shown = inputs.filter(visible);
        const passwords = shown.filter(input => input.type === "password");
        if (passwords.length > 1 || passwords.some(p => p.readOnly || p.autocomplete.includes("new-password"))) return;
        const password = passwords[0];
        const candidates = inputs.filter(input => userField(input) && (visible(input) || input.autocomplete.includes("username")) &&
          (!password || !!(input.compareDocumentPosition(password) & Node.DOCUMENT_POSITION_FOLLOWING)));
        const user = candidates.find(namedUser) ?? (password && root !== document.body ? candidates.at(-1) : undefined);
        if (!password && (!user || !namedUser(user) || user.readOnly)) return;
        return {root, user, password};
      }

      function targets() {
        const roots = new Set(document.forms);
        for (const input of document.querySelectorAll("input")) {
          if (visible(input) && (input.type === "password" || userField(input) && namedUser(input))) {
            const root = container(input);
            if (root) roots.add(root);
          }
        }
        return [...roots].slice(0, 32).map(root => fields(root)).filter(Boolean);
      }

      function update(input, value) {
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set.call(input, value);
        input.dispatchEvent(new Event("input", {bubbles: true}));
        input.dispatchEvent(new Event("change", {bubbles: true}));
      }

      function hide() {
        popup?.remove(); popup = popupOwner = focusMenu = undefined;
      }

      async function apply(target, username) {
        const before = fields(target.root);
        if (before?.user !== target.user || before?.password !== target.password || target.password?.value) return;
        if (target.user?.readOnly && target.user.value !== username) return;
        const originalUser = target.user?.value;
        const login = target.password
          ? await bridge.postMessage({operation: "fill", username, chosen: "true"}).catch(() => null)
          : {username};
        const current = fields(target.root);
        if (!login || current?.user !== target.user || current?.password !== target.password ||
            target.user?.value !== originalUser || target.password?.value) return;
        chosenUser = username;
        if (target.user && !target.user.readOnly && target.user.value !== username) update(target.user, username);
        if (target.password && fields(target.root)?.password === target.password && !target.password.value) update(target.password, login.password);
      }

      function show(target, accounts) {
        const owner = target.user === document.activeElement ? target.user : target.password;
        if (!owner || owner !== document.activeElement || !accounts.length) return;
        hide();
        popupOwner = owner;
        popup = document.createElement("div");
        popup.dataset.mybroPasswords = "";
        const rect = owner.getBoundingClientRect();
        popup.style.cssText = `position:fixed;left:${Math.max(8, Math.min(rect.left, innerWidth - 288))}px;top:${Math.max(8, Math.min(rect.bottom + 4, innerHeight - 180))}px;width:280px;z-index:2147483647`;
        const shadow = popup.attachShadow({mode: "closed"});
        const style = document.createElement("style");
        style.textContent = `:host{color-scheme:light dark} section{background:Canvas;color:CanvasText;border:1px solid GrayText;border-radius:8px;padding:4px;max-height:180px;overflow-y:auto;box-shadow:0 4px 16px #0004;font:13px system-ui} header{padding:8px;color:GrayText;font-size:12px} button{display:block;width:100%;border:0;border-radius:4px;padding:8px;text-align:left;background:transparent;color:inherit;font:inherit;overflow:hidden;text-overflow:ellipsis} button:hover,button:focus{background:Highlight;color:HighlightText;outline:0}`;
        const list = document.createElement("section");
        list.setAttribute("aria-label", "Сохранённые пароли myBro");
        const heading = document.createElement("header");
        heading.textContent = "Сохранённые пароли · myBro";
        list.append(heading);
        for (const username of accounts) {
          const button = document.createElement("button");
          button.type = "button";
          button.textContent = username || "Без логина";
          button.addEventListener("click", event => {
            if (!event.isTrusted) return;
            hide(); owner.focus(); apply(target, username);
          });
          list.append(button);
        }
        focusMenu = () => list.querySelector("button")?.focus();
        list.addEventListener("keydown", event => {
          const buttons = [...list.querySelectorAll("button")];
          const index = buttons.indexOf(shadow.activeElement);
          if (["ArrowDown", "ArrowUp"].includes(event.key)) {
            event.preventDefault();
            buttons[(index + (event.key === "ArrowDown" ? 1 : buttons.length - 1)) % buttons.length]?.focus();
          }
        });
        shadow.append(style, list);
        document.documentElement.append(popup);
      }

      async function fill(target) {
        const key = target.password ?? target.user;
        const username = target.user?.value ?? chosenUser ?? "";
        if (target.password?.value || pending.has(key) || attempts.get(key) === username) return;
        pending.add(key);
        try {
          accountRequest ??= bridge.postMessage({operation: "accounts", username: ""}).catch(() => null);
          const accounts = await accountRequest;
          if (!Array.isArray(accounts)) { accountRequest = undefined; return; }
          const current = fields(target.root);
          if (current?.user !== target.user || current?.password !== target.password || (target.user?.value ?? chosenUser ?? "") !== username) return;
          attempts.set(key, username);
          const exact = accounts.includes(username);
          if (exact || !username && accounts.length === 1) await apply(target, exact ? username : accounts[0]);
          else show(target, accounts.filter(user => !username || user.toLowerCase().startsWith(username.toLowerCase())));
        } finally { pending.delete(key); }
      }

      function scan() {
        clearTimeout(timer);
        timer = setTimeout(() => targets().forEach(fill), 100);
      }

      function refresh() {
        accountRequest = undefined;
        attempts = new WeakMap();
        scan();
      }
      globalThis.__myBroScanPasswords = refresh;

      function save(target) {
        const username = target?.user?.value ?? chosenUser ?? "";
        if (target?.password?.value) bridge.postMessage({operation: "save", username, password: target.password.value}).catch(() => {});
      }

      document.addEventListener("submit", event => {
        if (event.isTrusted) save(fields(event.target, event.submitter));
      }, true);
      document.addEventListener("click", event => {
        const button = event.target.closest?.("button,[role=button],input[type=submit]");
        if (!event.isTrusted || !button || button.form || !/войти|вход|продолжить|далее|log.?in|sign.?in|continue/i.test(button.textContent || button.value)) return;
        const target = targets().find(t => t.root.contains(button));
        if (target) save(target);
      }, true);
      document.addEventListener("keydown", event => {
        if (event.key === "Escape") hide();
        if (event.key === "ArrowDown" && popup && document.activeElement === popupOwner) {
          event.preventDefault();
          focusMenu?.();
        }
        if (event.isTrusted && event.key === "Enter" && document.activeElement?.type === "password") {
          save(targets().find(t => t.password === document.activeElement));
        }
      }, true);
      document.addEventListener("focusin", () => {
        if (document.activeElement === popup) return;
        hide(); refresh();
      });
      document.addEventListener("input", scan);
      document.addEventListener("change", scan);
      document.addEventListener("visibilitychange", refresh);
      document.addEventListener("scroll", hide, true);
      window.addEventListener("resize", hide);
      new MutationObserver(records => {
        if (records.some(record => record.target !== popup && !popup?.contains(record.target))) scan();
      }).observe(document.documentElement, {childList: true, subtree: true, attributes: true,
        attributeFilter: ["type", "autocomplete", "disabled", "readonly", "hidden", "class"]});
      scan();
    })();
    """#
}
