const assert = require("node:assert/strict");
const { mkdtemp, mkdir, readFile, rm, writeFile } = require("node:fs/promises");
const { createServer } = require("node:http");
const { tmpdir } = require("node:os");
const { join, resolve } = require("node:path");

const executable = process.argv[2];
const ublock = process.argv[3];
if (!executable) throw new Error("Usage: node Tests/chromium-smoke.cjs <Chromium executable> [unpacked uBlock Origin]");
const { chromium } = require(process.env.MYBRO_PLAYWRIGHT || "playwright");

async function writeExtension(root, version) {
    const extension = join(root, "mv" + version);
    await mkdir(extension);
    const manifest = {
        manifest_version: version,
        name: "myBro local test MV" + version,
        version: "1.0",
    };
    if (version === 2) {
        manifest.permissions = ["webRequest", "webRequestBlocking", "http://127.0.0.1/*"];
        manifest.background = { scripts: ["background.js"], persistent: true };
        await writeFile(join(extension, "background.js"), [
            "chrome.webRequest.onBeforeRequest.addListener(",
            "    () => ({cancel: true}),",
            '    {urls: ["http://127.0.0.1/*probe-ad.js"]},',
            '    ["blocking"]);',
        ].join("\n"));
    } else {
        manifest.content_scripts = [{ matches: ["http://127.0.0.1/*"], js: ["content.js"] }];
        await writeFile(join(extension, "content.js"), 'document.documentElement.dataset.mv3 = "ok";');
    }
    await writeFile(join(extension, "manifest.json"), JSON.stringify(manifest));
    return extension;
}

async function withProfile(profile, options, test) {
    const context = await chromium.launchPersistentContext(options.userData, {
        executablePath: resolve(executable),
        chromiumSandbox: true,
        ignoreDefaultArgs: ["--disable-extensions"],
        args: [
            "--no-first-run",
            "--no-proxy-server",
            "--host-resolver-rules=MAP mybro-smoke.test 127.0.0.1, MAP ad.doubleclick.net 127.0.0.1",
            "--enable-features=TabGroupsFocusing,NonGroupFocus",
            "--disable-features=VerticalTabs,TabGroupRibbon",
            "--profile-directory=" + profile,
            "--load-extension=" + options.extensions.join(","),
        ],
    });
    try {
        await test(context.pages()[0], context);
    } finally {
        await context.close();
    }
}

async function main() {
    const root = await mkdtemp(join(tmpdir(), "mybro-smoke-"));
    const server = createServer((request, response) => {
        response.setHeader("Cache-Control", "no-store");
        if (request.url === "/probe-ad.js") {
            response.setHeader("Content-Type", "text/javascript");
            response.end("window.probeAdLoaded = true;");
        } else if (request.url === "/ublock") {
            response.setHeader("Content-Type", "text/html");
            const port = server.address().port;
            response.end('<title>myBro uBlock test</title><script src="http://ad.doubleclick.net:' +
                port + '/probe-ad.js"></script>');
        } else {
            response.setHeader("Content-Type", "text/html");
            response.end('<title>myBro local test</title><script src="/probe-ad.js"></script>');
        }
    });
    try {
        await new Promise((onListen, onError) => server.once("error", onError).listen(0, "127.0.0.1", onListen));
        const origin = "http://127.0.0.1:" + server.address().port;
        const options = {
            userData: join(root, "profiles"),
            extensions: await Promise.all([writeExtension(root, 2), writeExtension(root, 3)]),
        };
        await withProfile("Default", options, async page => {
            const blocked = page.waitForEvent("requestfailed", {
                predicate: request => request.url() === origin + "/probe-ad.js",
                timeout: 10_000,
            }).catch(error => error);
            await page.goto(origin);
            await page.waitForFunction(() => document.documentElement.dataset.mv3 === "ok");
            assert.equal(await page.evaluate(() => window.probeAdLoaded), undefined);
            const failure = await blocked;
            if (failure instanceof Error) throw failure;
            assert.match(failure.failure().errorText, /ERR_BLOCKED_BY_CLIENT/);
            await page.evaluate(() => localStorage.setItem("mybro-profile", "Default"));
            console.log("PASS: MV2 webRequestBlocking and MV3 content script");
            await page.goto("chrome://extensions/");
            await page.getByText("myBro local test MV2", {exact: true}).waitFor({ timeout: 10_000 });
            await page.getByText("myBro local test MV3", {exact: true}).waitFor({ timeout: 10_000 });
            console.log("PASS: extension manager lists the MV2 and MV3 extensions");

            await page.goto("chrome://password-manager/passwords");
            await page.locator("#addPasswordButton").click({ timeout: 10_000 });
            await page.locator("#websiteInput input").fill("https://mybro-smoke.example");
            await page.locator("#usernameInput input").fill("mybro-test-user");
            await page.locator("#passwordInput input").fill("test-only-value");
            await page.locator("#addButton").click();
            await page.locator("password-list-item").first().waitFor({ timeout: 10_000 });
            console.log("PASS: native password manager adds a test login");
        });
        await withProfile("Profile 1", options, async page => {
            await page.goto(origin);
            assert.equal(await page.evaluate(() => localStorage.getItem("mybro-profile")), null);
            await page.goto("chrome://password-manager/passwords");
            await page.locator("#addPasswordButton").waitFor();
            assert.equal(await page.locator("password-list-item").count(), 0);
        });
        await withProfile("Default", options, async page => {
            await page.goto(origin);
            assert.equal(await page.evaluate(() => localStorage.getItem("mybro-profile")), "Default");
            await page.goto("chrome://password-manager/passwords");
            await page.locator("password-list-item").first().waitFor({ timeout: 10_000 });
        });
        const state = JSON.parse(await readFile(join(options.userData, "Local State"), "utf8"));
        for (const name of ["Default", "Profile 1"]) {
            assert.ok(state.profile.info_cache[name], "Unregistered profile " + name);
        }
        console.log("PASS: site data and test login persist and are isolated between profiles");

        if (ublock) {
            const testOrigin = "http://mybro-smoke.test:" + server.address().port;
            const ublockOptions = {
                userData: join(root, "ublock-profile"),
                extensions: [resolve(ublock)],
            };
            const getUblockOrigin = async settings => {
                await settings.goto("chrome://extensions/");
                const card = settings.locator("extensions-item").filter({
                    has: settings.getByRole("heading", { name: "uBlock Origin", exact: true }),
                });
                await card.waitFor({ timeout: 10_000 });
                const extensionId = await card.getAttribute("id");
                assert.match(extensionId, /^[a-p]{32}$/);
                return "chrome-extension://" + extensionId;
            };
            await withProfile("Default", ublockOptions, async (page, context) => {
                const settings = await context.newPage();
                await settings.goto(await getUblockOrigin(settings) + "/1p-filters.html");
                const manifest = await settings.evaluate(() => chrome.runtime.getManifest());
                assert.equal(manifest.name, "uBlock Origin");
                assert.equal(manifest.manifest_version, 2);
                await settings.waitForFunction(() =>
                    typeof chrome.extension.getBackgroundPage()?.vAPI?.net?.suspendableListener === "function",
                    undefined, { timeout: 10_000 }
                );
                const adScript = "http://ad.doubleclick.net:" + server.address().port + "/probe-ad.js";
                const blocked = page.waitForEvent("requestfailed", {
                    predicate: request => request.url() === adScript,
                    timeout: 10_000,
                }).catch(error => error);
                await page.bringToFront();
                await page.goto(testOrigin + "/ublock");
                assert.equal(await page.evaluate(() => window.probeAdLoaded), undefined,
                    "uBlock Origin allowed the local test script");
                const failure = await blocked;
                if (failure instanceof Error) throw failure;
                assert.match(failure.failure().errorText, /ERR_BLOCKED_BY_CLIENT/);
                console.log("PASS: uBlock Origin " + manifest.version + " MV2 blocked the local test script");
            });
        }
    } finally {
        server.close();
        await rm(root, { recursive: true, force: true });
    }
}

main().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
