{CompositeDisposable, BufferedProcess, NotificationManager} = require 'atom'
{MessagePanelView, LineMessageView, PlainMessageView} = require 'atom-message-panel'
{exec} = require 'child_process'
path = require 'path'

module.exports =
    config:
        povrayPath:
            type: 'string'
            default: 'povray'
            description: 'POV-Ray path'
        povrayArguments:
            type: 'string'
            default: '+Q11 +A -GS -GR'
            description: 'Default POV-Ray arguments'
        previewArguments:
            type: 'string'
            default: '+w1280 +h768 -V +P +Q11 +A -F'
            description: 'Arguments which are used when the preview is enabled'
        compileOnSave:
            type: 'boolean'
            default: 'true'
            description: 'Enable/Disable parsing on save'
        povrayPreview:
            type: 'boolean'
            default: 'true'
            description: 'Enable/Disable POV-Ray preview on save'
        unfoldBuildPanelOnError:
            type: 'boolean'
            default: 'true'
            description: 'Unfold build panel on error'
        buildPanelMaxHeight:
            type: 'number'
            default: '300'
            description: 'Max height of the build panel (px)'

    compilerProcess: null
    compilerMessages: []

    disposable: null

    activate: ->
        @messages = new MessagePanelView
            title: 'POV-Ray build panel. (F8 : Parse a .pov script)'
            position: 'bottom'
            maxHeight: atom.config.get('tools-povray.buildPanelMaxHeight') + "px"
            rawTitle: true

        @messages.attach()
        @messages.toggle()
        @messages.hide()

        active_text_editor = atom.workspace.getActiveTextEditor()
        if active_text_editor
            if @validPOVRayFile(active_text_editor.getPath() or '')
                @messages.show()
            else
                @messages.hide()
        else
            @messages.hide()

        atom.workspace.onDidChangeActivePaneItem (editor) =>
            if editor
                if editor.getPath
                    if @validPOVRayFile(editor.getPath() or '')
                        @messages.show()
                    else
                        @messages.hide()
                else
                    @messages.hide()
            else
                @messages.hide()

        atom.workspace.observeTextEditors (editor) =>
            validPOVRayFile = @validPOVRayFile
            editor.onDidSave ->
                if atom.config.get('tools-povray.compileOnSave')
                    if editor
                        if editor.getPath
                            if validPOVRayFile(editor.getPath() or '')
                                atom.commands.dispatch(atom.views.getView(editor), 'povray:parse')

        @disposable = atom.commands.add 'atom-text-editor', 'povray:parse': (event) =>
            active_text_editor = atom.workspace.getActiveTextEditor()
            full_file_path = ""
            if active_text_editor
                full_file_path = active_text_editor.getPath()
                if !@validPOVRayFile(full_file_path)
                    return
            else
                return
            args = []
            args = args.concat (atom.config.get('tools-povray.povrayArguments').split(" "))
            if atom.config.get('tools-povray.povrayPreview')
                args = args.concat (atom.config.get('tools-povray.previewArguments').split(" "))
            if process.platform == "win32"
                args.push "/RENDER"
            args.push "\""+full_file_path+"\""

            @compile(path.dirname(full_file_path), args)

        console.log 'tools-povray activated' if atom.inDevMode()

    deactivate: ->
        @messages.close()
        @disposable.dispose()

    validPOVRayFile: (filepath) ->
        ext = path.extname(filepath)
        if ext == '.pov'
           return true
        return false

    toHtml: (str) ->
        return str.replace(/(?:\r\n|\r|\n)/g, '<br />')

    parseCompilerOutput: ->
        @messages.clear()

        @compilerMessages = @compilerMessages.join "\n"

        compilerMessageRegex = /File '([\na-zA-z\.\d:\/\\-]+)' line (\d+): Parse (Warning|Error): ([a-zA-z#_\.\d\s\/{}()',"<>=\-]+)(?=Fatal|File|$)/gm

        warnings = 0
        errors = 0

        while((messages_arr = compilerMessageRegex.exec(@compilerMessages)) != null)
            msg_type = messages_arr[3]

            color = ""
            if msg_type == "Warning"
                warnings += 1
                color = "yellow"
            else if msg_type == "Error"
                errors += 1
                color = "red"

            message = msg_type + ": " + messages_arr[4].replace(/(?:\r\n|\r|\n)/g, '')

            @messages.add new LineMessageView
                file: messages_arr[1].replace(/(?:\r\n|\r|\n)/g, '')
                line: messages_arr[2]
                preview: message
                color: color

        title = "<span style='font-weight: bold;'>Build failed.</span>"

        if warnings > 0 || errors > 0
            title += "&nbsp;"

        if errors > 0
            title += "<span style='color: red;'>" + errors + " <span font-weight: bold;'>Error</span> </span>"
            if atom.config.get 'tools-povray.unfoldBuildPanelOnError'
              @messages.unfold()
        else
            title = "<span style='color: green; font-weight: bold;'>Build successful."
            title += "</span>"
            @compilerMessages = @toHtml @compilerMessages
            @messages.add new PlainMessageView
                message: @compilerMessages
                raw: true

        if warnings > 0
            title += "<span style='color: yellow;'>" + warnings + " <span font-weight: bold;'>Warning</span> </span>"

        @messages.setTitle(title, true)

        @compilerMessages = []

    compile: (cwd, args) ->
        @messages.clear()

        if @compilerProcess
            @compilerProcess.kill()
            @compilerProcess = null

        options =
            cwd: cwd
            env: process.env
            shell: true
        command = "\"" + atom.config.get('tools-povray.povrayPath') + "\""

        @messages.setTitle('<span style="font-weight: bold; color: white;">Building ' + args[0] + ' ...</span>', true)

        stdout = (output) =>
            @messages.add new PlainMessageView
                message: output
            @compilerMessages.push(output)
        stderr = (output) =>
            @messages.add new PlainMessageView
                message: output
            @compilerMessages.push(output)
        exit = (code) =>
            @parseCompilerOutput()
        @compilerProcess = new BufferedProcess({command, args, options, stdout, stderr, exit})
        @compilerProcess.onWillThrowError (err) =>
            return unless err?
                if err.error.code is 'ENOENT'
                    notification_options =
                        detail: "Could not compile the file '" + args[0] + "' because POV-Ray was not found. (check your path/installation)"
                    atom.notifications.addError "POV-Ray was not found", notification_options
                    @messages.setTitle(notification_options.detail)
