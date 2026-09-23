pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Everything the panel knows, and every command it starts. Nothing here draws,
// and nothing here reads a plugin's files: the catalog comes from
// `lib/catalog.sh list` and a plugin's verdicts from
// `omarchy-plugin-audit --json`, both parsed as data by Model.js.
//
// One instance (qmldir makes this a singleton), so the catalog is parsed once
// and kept across opens instead of on every keypress of the keybinding.
Singleton {
  id: root

  // This plugin's own folder, from this file's URL: every argv points into it.
  readonly property string pluginDir: decodeURIComponent(
    Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")).replace(/\/$/, "")
  // The same root-owned PATH the bar widget gives its children.
  readonly property var childEnv: ({
    "PATH": "/run/wrappers/bin:/run/current-system/sw/bin:/etc/profiles/per-user/"
            + (Quickshell.env("USER") || "") + "/bin"
  })

  // ------------------------------------------------------------ catalog
  property var rows: []
  property bool loading: false
  property string catalogError: ""
  property double loadedAt: 0
  readonly property int staleAfterMs: 3600 * 1000

  function ensureCatalog() {
    if (root.rows.length === 0 || Date.now() - root.loadedAt > root.staleAfterMs) loadCatalog(false)
  }

  function loadCatalog(refresh) {
    if (catalogProcess.running) return
    root.loading = true
    root.catalogError = ""
    catalogProcess.command = Model.catalogArgv(root.pluginDir, refresh)
    catalogProcess.running = true
  }

  function rowFor(id) {
    for (var i = 0; i < root.rows.length; i++) if (root.rows[i].id === id) return root.rows[i]
    return null
  }

  Process {
    id: catalogProcess
    environment: root.childEnv
    stdout: StdioCollector { id: catalogOut; waitForEnd: true }
    stderr: StdioCollector { id: catalogErr; waitForEnd: true }
    onExited: function(code) {
      root.loading = false
      var parsed = code === 0 ? Model.parseRows(catalogOut.text) : null
      if (!parsed) {
        root.catalogError = Model.lastLines(catalogErr.text, 1) || ("catalog failed (exit " + code + ")")
        return
      }
      root.rows = parsed
      root.loadedAt = Date.now()
    }
  }

  // ------------------------------------------------------------ audit
  // One audit at a time. Asking for another while one runs queues the newest,
  // so moving through the list never waits on a plugin you already left.
  property var report: null
  property string reportFor: ""
  property bool auditing: false
  property string auditingFor: ""
  property string auditError: ""
  property string pendingAudit: ""

  function audit(id) {
    if (!Model.isSafeId(id)) return
    if (auditProcess.running) { root.pendingAudit = id; return }
    root.auditing = true
    root.auditingFor = id
    root.auditError = ""
    auditProcess.command = Model.auditArgv(root.pluginDir, id)
    auditProcess.running = true
  }

  Process {
    id: auditProcess
    environment: root.childEnv
    stdout: StdioCollector { id: auditOut; waitForEnd: true }
    stderr: StdioCollector { id: auditErr; waitForEnd: true }
    onExited: function(code) {
      // 0 passed, 10 review-required, 20 needs-fixes: all are reports.
      var r = (code === 0 || code === 10 || code === 20) ? Model.parseReport(auditOut.text) : null
      root.reportFor = root.auditingFor
      root.report = r
      root.auditError = r ? "" : (Model.lastLines(auditErr.text, 2) || ("audit failed (exit " + code + ")"))
      root.auditing = false
      if (root.pendingAudit !== "") {
        var next = root.pendingAudit
        root.pendingAudit = ""
        root.audit(next)
      }
    }
  }

  // ------------------------------------------------------------ preview
  // The plugin's marketplace thumbnail. catalog.sh fetches and checks it and
  // prints a local file; the shell only ever decodes that verified file. One
  // fetch at a time, newest request queued, as the audit does.
  readonly property string previewDir: (Quickshell.env("XDG_CACHE_HOME")
    || (Quickshell.env("HOME") + "/.cache")) + "/omarchy-plugin-audit/previews/"
  property string previewFor: ""
  property string previewPath: ""
  property bool previewing: false
  property string previewingFor: ""
  property var pendingPreview: null

  function preview(row) {
    root.previewFor = row ? row.id : ""
    root.previewPath = ""
    var argv = row && Model.isSafeId(row.id) ? Model.previewArgv(root.pluginDir, row.preview) : null
    if (!argv) return
    if (previewProcess.running) { root.pendingPreview = row; return }
    root.previewing = true
    root.previewingFor = row.id
    previewProcess.command = argv
    previewProcess.running = true
  }

  Process {
    id: previewProcess
    environment: root.childEnv
    stdout: StdioCollector { id: previewOut; waitForEnd: true }
    onExited: function(code) {
      var path = String(previewOut.text || "").trim()
      // Only a file catalog.sh verified, under its own cache folder, and only
      // for the plugin still open: a late answer for another plugin is dropped.
      if (code === 0 && path.indexOf(root.previewDir) === 0 && path.indexOf("..") < 0
          && root.previewingFor === root.previewFor)
        root.previewPath = path
      root.previewing = false
      if (root.pendingPreview) {
        var next = root.pendingPreview
        root.pendingPreview = null
        if (next.id === root.previewFor) root.preview(next)
      }
    }
  }

  // ------------------------------------------------------------ install
  property bool installing: false
  property string installFor: ""
  property string installOutput: ""

  function install(id) {
    if (!Model.isSafeId(id) || installProcess.running) return
    root.installing = true
    root.installFor = id
    root.installOutput = ""
    installProcess.command = Model.installArgv(root.pluginDir, id)
    installProcess.running = true
  }

  Process {
    id: installProcess
    environment: root.childEnv
    stdout: StdioCollector { id: installOut; waitForEnd: true }
    stderr: StdioCollector { id: installErr; waitForEnd: true }
    onExited: function(code) {
      root.installing = false
      root.installOutput = Model.lastLines(installOut.text + "\n" + installErr.text, 6)
                           || ("install exited " + code)
    }
  }

  // ------------------------------------------------------------ detached
  function agent(id, mode) {
    if (!Model.isSafeId(id)) return false
    Quickshell.execDetached({ command: Model.agentArgv(root.pluginDir, id, mode), environment: root.childEnv })
    return true
  }

  function copy(text) {
    if (String(text || "") === "") return false
    Quickshell.execDetached({ command: Model.copyArgv(text), environment: root.childEnv })
    return true
  }

  function openRepo(repo) {
    var argv = Model.openArgv(repo)
    if (!argv) return false
    Quickshell.execDetached({ command: argv, environment: root.childEnv })
    return true
  }
}
