-- Huge credits to mrcjkb
-- https://github.com/mrcjkb/rustaceanvim/blob/2fa45427c01ded4d3ecca72e357f8a60fd8e46d4/lua/rustaceanvim/commands/init.lua
local M = {}

local cmd_name = "Roslyn"

---@class RoslynSubcommandTable
---@field impl fun(args: string[], opts: vim.api.keyset.user_command) The command implementation
---@field complete? fun(subcmd_arg_lead: string): string[] Command completions callback, taking the lead of the subcommand's arguments

---@type RoslynSubcommandTable[]
local subcommand_tbl = {
    restart = {
        impl = function()
            local client = vim.lsp.get_clients({ name = "roslyn" })[1]
            if not client then
                return
            end

            local attached_buffers = vim.tbl_keys(client.attached_buffers)

            -- TODO: Change this to `client:request` when minimal version is `0.11`
            ---@diagnostic disable-next-line: missing-parameter
            client.stop()

            local timer = vim.uv.new_timer()
            timer:start(
                500,
                100,
                vim.schedule_wrap(function()
                    -- TODO: Change this to `client:request` when minimal version is `0.11`
                    ---@diagnostic disable-next-line: missing-parameter
                    if client.is_stopped() then
                        for _, buffer in ipairs(attached_buffers) do
                            vim.api.nvim_exec_autocmds("FileType", { group = "Roslyn", buffer = buffer })
                        end
                    end

                    if not timer:is_closing() then
                        timer:close()
                    end
                end)
            )
        end,
    },
    stop = {
        impl = function()
            local client = vim.lsp.get_clients({ name = "roslyn" })[1]
            if not client then
                return
            end

            -- TODO: Change this to `client:request` when minimal version is `0.11`
            ---@diagnostic disable-next-line: missing-parameter, param-type-mismatch
            client.stop(true)
        end,
    },
    target = {
        impl = function()
            local bufnr = vim.api.nvim_get_current_buf()
            local root = vim.b.roslyn_root or require("roslyn.sln.utils").root(bufnr)

            local roslyn_lsp = require("roslyn.lsp")

            local targets = vim.iter({ root.solutions, root.solution_filters }):flatten():totable()

            local pickers = require("telescope.pickers")
            local finders = require("telescope.finders")
            local conf = require("telescope.config").values
            local actions = require("telescope.actions")
            local action_state = require("telescope.actions.state")

            pickers.new({}, {
                prompt_title = "Select a target",
                finder = finders.new_table { results = targets, },
                sorter = conf.generic_sorter(),
                attach_mappings = function(prompt_bufnr)
                    actions.select_default:replace(function()
                        local selection = action_state.get_selected_entry()
                        actions.close(prompt_bufnr)
                        vim.lsp.stop_client(vim.lsp.get_clients({ name = "roslyn" }), true)
                        vim.g.roslyn_nvim_selected_solution = selection.value
                        local sln_dir = vim.fs.dirname(selection.value)
                        roslyn_lsp.start(bufnr, assert(sln_dir), roslyn_lsp.on_init_sln)
                    end)
                    return true
                end,
            }):find()
        end,
    },
}

---@param opts table
---@see vim.api.nvim_create_user_command
local function roslyn(opts)
    local fargs = opts.fargs
    local cmd = fargs[1]
    local args = #fargs > 1 and vim.list_slice(fargs, 2, #fargs) or {}
    local subcommand = subcommand_tbl[cmd]
    if type(subcommand) == "table" and type(subcommand.impl) == "function" then
        subcommand.impl(args, opts)
        return
    end

    vim.notify(cmd_name .. ": Unknown subcommand: " .. cmd, vim.log.levels.ERROR, { title = "roslyn.nvim" })
end

function M.create_roslyn_commands()
    vim.api.nvim_create_user_command(cmd_name, roslyn, {
        nargs = "+",
        range = true,
        desc = "Interacts with Roslyn",
        complete = function(arg_lead, cmdline, _)
            local all_commands = vim.tbl_keys(subcommand_tbl)

            local subcmd, subcmd_arg_lead = cmdline:match("^" .. cmd_name .. "[!]*%s(%S+)%s(.*)$")
            if subcmd and subcmd_arg_lead and subcommand_tbl[subcmd] and subcommand_tbl[subcmd].complete then
                return subcommand_tbl[subcmd].complete(subcmd_arg_lead)
            end

            if cmdline:match("^" .. cmd_name .. "[!]*%s+%w*$") then
                return vim.tbl_filter(function(command)
                    return command:find(arg_lead) ~= nil
                end, all_commands)
            end
        end,
    })
end

return M
