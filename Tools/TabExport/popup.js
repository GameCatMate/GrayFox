const button = document.getElementById("export");
const status = document.getElementById("status");

async function snapshot() {
    const openTabs = (await chrome.tabs.query({})).filter(tab => !tab.incognito);
    const tabs = openTabs.flatMap(tab => {
        const url = [tab.url, tab.pendingUrl].find(candidate => {
            try {
                const parsed = new URL(candidate);
                return ["https:", "http:"].includes(parsed.protocol) && !parsed.username && !parsed.password;
            } catch {
                return false;
            }
        });
        return url ? [{
            window: tab.windowId,
            index: tab.index,
            group: tab.groupId >= 0 ? tab.groupId : null,
            pinned: Boolean(tab.pinned),
            title: tab.title ?? "",
            url,
        }] : [];
    });

    let groups = [];
    if (chrome.tabGroups?.query) {
        const visibleGroups = new Set(tabs.filter(tab => tab.group !== null).map(tab => `${tab.window}:${tab.group}`));
        try {
            groups = (await chrome.tabGroups.query({}))
                .filter(group => visibleGroups.has(`${group.windowId}:${group.id}`))
                .map(group => ({
                    id: group.id,
                    window: group.windowId,
                    title: group.title ?? "",
                    color: group.color ?? "grey",
                }));
        } catch {
            // Export the tabs even when this browser does not expose group details.
        }
    }
    return { version: 1, tabs, groups, skipped: openTabs.length - tabs.length };
}

button.addEventListener("click", async () => {
    button.disabled = true;
    try {
        const report = await snapshot();
        const file = new Blob([JSON.stringify(report, null, 2)], { type: "application/json" });
        const url = URL.createObjectURL(file);
        const link = document.createElement("a");
        link.href = url;
        link.download = "mybro-tabs.json";
        link.click();
        setTimeout(() => URL.revokeObjectURL(url), 10_000);
        status.textContent = `Вкладок: ${report.tabs.length}. Групп: ${report.groups.length}. Пропущено: ${report.skipped}.`;
    } catch {
        status.textContent = "Не удалось экспортировать вкладки.";
    } finally {
        button.disabled = false;
    }
});
