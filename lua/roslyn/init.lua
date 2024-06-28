local function bufname_valid(bufname)
    return bufname:match("^/")
        or bufname:match("^[a-zA-Z]:")
        or bufname:match("^zipfile://")
        or bufname:match("^tarfile:")
end

local function lsp_start(exe, target, server_config)
    local stdout_handler = function(_, data)
        if not data then
            vim.notify(string.format("data evaluates: (%s, %s) ", #data, data[1]), vim.log.levels.INFO)
            return
        end

        -- try parse data as json
        local success, json_obj = pcall(vim.json.decode, data)
        if not success then
            return
        end

        local pipe_name = json_obj["pipeName"]
        if not pipe_name then
            return
        end

        vim.schedule(function()
            local client_id = vim.lsp.start({
                name = "roslyn",
                capabilities = server_config.capabilities,
                settings = server_config.settings,
                cmd = vim.lsp.rpc.connect(pipe_name),
                root_dir = vim.fs.dirname(target),
                on_init = function(client)
                    vim.notify("Roslyn client initialized for " .. target, vim.log.levels.INFO)
                    client.notify("solution/open", {
                        ["solution"] = vim.uri_from_fname(target),
                    })
                end,
                handlers = {
                    [vim.lsp.protocol.Methods.client_registerCapability] = require("roslyn.hacks").with_filtered_watchers(
                        vim.lsp.handlers[vim.lsp.protocol.Methods.client_registerCapability]
                    ),
                    ["workspace/projectInitializationComplete"] = function()
                        vim.notify("Roslyn project initialization complete", vim.log.levels.INFO)
                    end,
                    ["workspace/_roslyn_projectHasUnresolvedDependencies"] = function()
                        vim.notify("Detected missing dependencies. Run dotnet restore command.", vim.log.levels.ERROR)
                        return vim.NIL
                    end,
                },
            })

            -- Handle the error in some way
            if not client_id then
                return
            end

            local client = vim.lsp.get_client_by_id(client_id)
            if not client then
                return
            end

            local commands = require("roslyn.commands")
            commands.fix_all_code_action(client)
            commands.nested_code_action(client)
        end)
    end

    vim.system({
        "dotnet",
        exe,
        "--logLevel=Information",
        "--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path()),
    }, {
        stdout = stdout_handler,
        stderr_handler = function(_, chunk)
            local log = require("vim.lsp.log")
            if chunk and log.error() then
                log.error("rpc", "dotnet", "stderr", chunk)
            end
        end,
        detach = not vim.uv.os_uname().version:find("Windows"),
    })
end

-- Assigns the default capabilities from cmp if installed, and the capabilities from neovim
-- Merges it in with any user configured capabilities if provided
local function get_default_capabilities()
    local ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
    local capabilities = ok
            and vim.tbl_deep_extend(
                "force",
                vim.lsp.protocol.make_client_capabilities(),
                cmp_nvim_lsp.default_capabilities()
            )
        or vim.lsp.protocol.make_client_capabilities()

    -- HACK: Roslyn requires the dynamicRegistration to be set to support diagnostics for some reason
    return vim.tbl_deep_extend("force", capabilities, {
        textDocument = {
            diagnostic = {
                dynamicRegistration = true,
            },
        },
    })
end

local M = {}

function M.setup(config)
    local default_config = {
        capabilities = get_default_capabilities(),
        exe = vim.fs.joinpath(
            vim.fn.stdpath("data") --[[@as string]],
            "roslyn",
            "Microsoft.CodeAnalysis.LanguageServer.dll"
        ),
    }

    local solution = {}

    local server_config = vim.tbl_deep_extend("force", default_config, config or {})

    vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("Roslyn", { clear = true }),
        pattern = { "cs" },
        callback = function(opt)
            local bufname = vim.api.nvim_buf_get_name(opt.buf)

            if vim.bo["buftype"] == "nofile" or not bufname_valid(bufname) then
                return
            end

            local exe = server_config.exe
            if not vim.uv.fs_stat(exe) then
                return vim.notify(
                    string.format("%s not found. Refer to README on how to setup the language server", exe),
                    vim.log.levels.INFO
                )
            end

            local sln_dir = vim.fs.root(opt.buf, function(name)
                return name:match("%.sln$") ~= nil
            end)
            if not sln_dir then
                return
            end

            if solution[sln_dir] then
                return lsp_start(exe, solution[sln_dir], server_config)
            end

            -- Finds possible targets
            local targets = vim.fn.glob(vim.fs.joinpath(sln_dir, "*.sln"), true, true)

            if #targets == 1 then
                lsp_start(exe, targets[1], server_config)
                solution[sln_dir] = targets[1]
            elseif #targets > 1 then
                vim.notify("Multiple targets found. Use `CSTarget` to select target for buffer", vim.log.levels.INFO)
                vim.api.nvim_create_user_command("CSTarget", function()
                    vim.ui.select(targets, { prompt = "Select target: " }, function(target)
                        lsp_start(exe, target, server_config)
                        solution[sln_dir] = target
                    end)
                end, { desc = "Selects the target for the current buffer" })
            end
        end,
    })
end

return M
