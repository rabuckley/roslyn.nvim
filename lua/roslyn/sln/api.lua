local M = {}

local sysname = vim.uv.os_uname().sysname:lower()
local iswin = not not (sysname:find("windows") or sysname:find("mingw"))

---@param solution string Path to solution
---@return string[] Table of projects in given solution
function M.solution_projects(solution)
    local file = io.open(solution, "r")
    if not file then
        return {}
    end

    local paths = {}

    for line in file:lines() do
        local id, name, path = line:match('Project%("{(.-)}"%).*= "(.-)", "(.-)", "{.-}"')
        if id and name and path and path:match("%.csproj$") then
            local normalized_path = iswin and path or path:gsub("\\", "/")
            local dirname = vim.fs.dirname(solution)
            local fullpath = vim.fs.joinpath(dirname, normalized_path)
            local normalized = vim.fs.normalize(fullpath)
            table.insert(paths, normalized)
        end
    end

    file:close()

    return paths
end

---@param solution_filter string Path to solution filter
---@return string[] Table of projects in given solution filter
function M.solution_filter_projects(solution_filter)
    local file = io.open(solution_filter, "r")
    if not file then
        return {}
    end

    local paths = {}

    for line in file:lines() do
        local path = line:match('"(.*%.csproj)"')
        if path then
            local normalized_path = iswin and path or path:gsub("\\", "/")
            local dirname = vim.fs.dirname(solution_filter)
            local fullpath = vim.fs.joinpath(dirname, normalized_path)
            local normalized = vim.fs.normalize(fullpath)
            table.insert(paths, normalized)
        end
    end

    file:close()

    return paths
end

---Checks if a project is part of a solution filter or not
---@param solution_filter string
---@param project string Full path to the csproj file
---@return boolean
function M.exists_in_solution_filter(solution_filter, project)
    local projects = M.solution_filter_projects(solution_filter)

    return vim.iter(projects):find(function(it)
        return it == project
    end) ~= nil
end

---Checks if a project is part of a solution or not
---@param solution string
---@param project string Full path to the csproj file
---@return boolean
function M.exists_in_solution(solution, project)
    local projects = M.solution_projects(solution)

    return vim.iter(projects):find(function(it)
        return it == project
    end) ~= nil
end

return M
