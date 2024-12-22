local M = {}

--- Searches for files with a specific extension within a directory.
--- Only files matching the provided extension are returned.
---
--- @param dir string The directory path for the search.
--- @param extension string The file extension to look for (e.g., ".sln").
---
--- @return string[] List of file paths that match the specified extension.
local function find_files_with_extension(dir, extension)
    local matches = {}

    for entry, type in vim.fs.dir(dir) do
        if type == "file" and vim.endswith(entry, extension) then
            matches[#matches + 1] = vim.fs.normalize(vim.fs.joinpath(dir, entry))
        end
    end

    return matches
end

---@class RoslynNvimDirectoryWithFiles
---@field directory string
---@field files string[]

---@class RoslynNvimRootDir
---@field projects? RoslynNvimDirectoryWithFiles
---@field solutions? string[]
---@field solution_filters? string[]

---@param buffer integer
---@return RoslynNvimRootDir
function M.root(buffer)
    local broad_search = require("roslyn.config").get().broad_search

    local sln = vim.fs.root(buffer, function(name)
        return name:match("%.sln$") ~= nil
    end)

    local slnf = vim.fs.root(buffer, function(name)
        return name:match("%.sln$") ~= nil
    end)

    local csproj = vim.fs.root(buffer, function(name)
        return name:match("%.csproj$") ~= nil
    end)

    if not sln and not csproj then
        return {}
    end

    local projects = csproj and { files = find_files_with_extension(csproj, ".csproj"), directory = csproj } or nil

    if not broad_search then
        if not sln and not slnf then
            return {
                solutions = nil,
                solution_filters = nil,
                projects = projects,
            }
        end

        return {
            solutions = find_files_with_extension(sln, ".sln"),
            solution_filters = find_files_with_extension(slnf, ".slnf"),
            projects = projects,
        }
    end

    local git_root = vim.fs.root(buffer, ".git")
    local search_root = git_root and sln:match(git_root) and git_root or sln

    local solutions = vim.fs.find(function(name, _)
        return name:match("%.sln$")
    end, { type = "file", limit = math.huge, path = search_root })


    local solution_filters = vim.fs.find(function(name, _)
        return name:match("%.slnf$")
    end, { type = "file", limit = math.huge, path = search_root })

    return {
        solutions = solutions,
        solution_filters = solution_filters,
        projects = projects,
    }
end

---Tries to predict which solution or solution filter to use if we found some
---returning the potentially predicted solution/solution filter.
---Notifies the user if we still have multiple to choose from
---@param root RoslynNvimRootDir
---@return boolean multiple_potential_targets, string? target
function M.predict_target(root)
    if not root.solutions and not root.solution_filters then
        return true, nil
    end

    local config = require("roslyn.config").get()

    local solutions = vim.iter(root.solutions)
        :filter(function(solution)
            if config.ignore_target and config.ignore_target(solution) then
                return false
            end
            return not root.projects
                or vim.iter(root.projects.files):any(function(csproj_file)
                    return require("roslyn.sln.api").exists_in_solution(solution, csproj_file)
                end)
        end)
        :totable()

    local solution_filters = vim.iter(root.solution_filters)
        :filter(function(solution_filter)
            if config.ignore_target and config.ignore_target(solution_filter) then
                return false
            end
            return not root.projects
                or vim.iter(root.projects.files):any(function(csproj_file)
                    return require("roslyn.sln.api").exists_in_solution_filter(solution_filter, csproj_file)
                end)
        end)
        :totable()

    if #solutions == 1 and #solution_filters == 0 then
        return false, solutions[1]
    end

    local chosen = config.choose_target and
        config.choose_target(vim.iter({ solutions, solution_filters }):flatten():totable()) or nil

    if chosen then
        return false, chosen
    end

    vim.notify(
        "Multiple target files found. Use `:Roslyn target` to select or change target for buffer",
        vim.log.levels.INFO,
        { title = "roslyn.nvim" }
    )

    return true, nil
end

return M
