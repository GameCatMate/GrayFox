import WebKit

@MainActor enum TabAudio {
    private static let marker = "/* myBro.TabAudio */"

    static func install(in controller: WKUserContentController, muted: Bool) {
        let others = controller.userScripts.filter { !$0.source.hasPrefix(marker) }
        controller.removeAllUserScripts()
        for script in others { controller.addUserScript(script) }
        controller.addUserScript(WKUserScript(source: marker + "\n" + script(muted: muted),
                                              injectionTime: .atDocumentStart, forMainFrameOnly: false))
    }

    static func update(_ web: WKWebView, muted: Bool) {
        install(in: web.configuration.userContentController, muted: muted)
        web.evaluateJavaScript("globalThis.__myBroSetAudioMuted?.(\(muted))", completionHandler: nil)
    }

    private static func script(muted: Bool) -> String {
        """
        (() => {
          if (globalThis.__myBroSetAudioMuted) return;
          let muted = \(muted);
          const previous = new WeakMap();
          const descriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'muted');
          function apply(media) {
            if (muted) {
              if (!previous.has(media)) previous.set(media, descriptor.get.call(media));
              descriptor.set.call(media, true);
            } else if (previous.has(media)) {
              descriptor.set.call(media, previous.get(media));
              previous.delete(media);
            }
          }
          Object.defineProperty(HTMLMediaElement.prototype, 'muted', {
            ...descriptor,
            set(value) {
              if (muted) previous.set(this, Boolean(value));
              descriptor.set.call(this, muted || value);
            }
          });
          function scan(root) {
            if (root instanceof HTMLMediaElement) apply(root);
            root.querySelectorAll?.('audio,video').forEach(apply);
          }
          new MutationObserver(records => {
            for (const record of records) for (const node of record.addedNodes) scan(node);
          }).observe(document, {childList: true, subtree: true});
          document.addEventListener('play', event => {
            if (event.target instanceof HTMLMediaElement) apply(event.target);
          }, true);

          // shortcut: WebKit has no public tab audio mute; Web Audio is suspended while muted.
          const contexts = new Map();
          for (const name of ['AudioContext', 'webkitAudioContext']) {
            const Constructor = globalThis[name];
            if (!Constructor) continue;
            globalThis[name] = new Proxy(Constructor, {
              construct(target, args, newTarget) {
                const context = Reflect.construct(target, args, newTarget);
                const resume = context.resume.bind(context), suspend = context.suspend.bind(context);
                const state = {resume, suspend, wanted: context.state === 'running'};
                contexts.set(context, state);
                context.resume = (...args) => {
                  state.wanted = true;
                  return muted ? Promise.resolve() : resume(...args);
                };
                context.suspend = (...args) => { state.wanted = false; return suspend(...args); };
                context.addEventListener('statechange', () => {
                  if (context.state === 'closed') contexts.delete(context);
                });
                if (muted) suspend().catch(() => {});
                return context;
              }
            });
          }
          globalThis.__myBroSetAudioMuted = value => {
            const changed = muted !== Boolean(value);
            muted = Boolean(value);
            scan(document);
            if (changed) for (const [context, state] of contexts) {
              if (muted) {
                state.wanted = context.state === 'running';
                state.suspend().catch(() => {});
              } else if (state.wanted) state.resume().catch(() => {});
            }
            for (let i = 0; i < frames.length; i++) {
              frames[i].postMessage({myBroAudioMuted: muted}, '*');
            }
          };
          addEventListener('message', event => {
            if (window !== parent && event.source === parent && typeof event.data?.myBroAudioMuted === 'boolean') {
              __myBroSetAudioMuted(event.data.myBroAudioMuted);
            }
          });
          scan(document);
        })();
        """
    }
}
