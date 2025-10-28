-- lua/java-creator-nvim/init.lua
local M = {}

-- Default configuration
M.config = {
	templates = {
		class = [[package %s;

public class %s {
    
}]],
		interface = [[package %s;

public interface %s {
    
}]],
		enum = [[package %s;

public enum %s {
    
}]],
		record = [[package %s;

public record %s() {
    
}]],
		abstract_class = [[package %s;

public abstract class %s {
    
}]],
	},

	keymaps = {
		java_new = "<leader>jn",
		java_class = "<leader>jc",
		java_interface = "<leader>ji",
		java_enum = "<leader>je",
		java_record = "<leader>jr",
	},

	options = {
		auto_open = true,
		use_notify = true, -- Set to false to disable all notifications from this plugin
		notification_timeout = 3000, -- Timeout for notifications in milliseconds
		java_version = 17,
		src_patterns = { "src/main/java", "src/test/java", "src" },
	},
}

local utils = {}

---
--- Sends a notification to the user if enabled in the config.
--- Uses 'nvim-notify' if available, otherwise falls back to vim.notify.
---
---@param msg string The message to display.
---@param level vim.log.levels The notification level (e.g., INFO, ERROR).
function utils.notify(msg, level)
	if not M.config.options.use_notify then
		return -- Do nothing if notifications are disabled
	end

	level = level or vim.log.levels.INFO

	local ok, notify_lib = pcall(require, "notify")
	if ok then
		-- Use 'nvim-notify' if available
		notify_lib(msg, level, {
			title = "Java Creator",
			timeout = M.config.options.notification_timeout,
		})
	else
		-- Fallback to the standard vim.notify
		vim.notify(msg, level, { title = "Java Creator", level = level })
	end
end

---
--- Displays an error message.
---
---@param msg string The error message.
function utils.error(msg)
	utils.notify(msg, vim.log.levels.ERROR)
end

---
--- Displays an informational message.
---
---@param msg string The info message.
function utils.info(msg)
	utils.notify(msg, vim.log.levels.INFO)
end

---
--- Displays a warning message.
---
---@param msg string The warning message.
function utils.warn(msg)
	utils.notify(msg, vim.log.levels.WARN)
end

---
--- Validates if a string is a valid Java identifier and not a keyword.
---
---@param name string The identifier to validate.
---@return boolean, string|nil True if valid, false and an error message otherwise.
function utils.validate_java_name(name)
	if not name or name == "" then
		return false, "Name cannot be empty"
	end
	if not name:match("^[a-zA-Z_]") then
		return false, "Name must start with a letter or underscore"
	end
	if not name:match("^[a-zA-Z0-9_]*$") then
		return false, "Name can only contain letters, numbers, and underscores"
	end

	local java_keywords = {
		"abstract",
		"assert",
		"boolean",
		"break",
		"byte",
		"case",
		"catch",
		"char",
		"class",
		"const",
		"continue",
		"default",
		"do",
		"double",
		"else",
		"enum",
		"extends",
		"final",
		"finally",
		"float",
		"for",
		"goto",
		"if",
		"implements",
		"import",
		"instanceof",
		"int",
		"interface",
		"long",
		"native",
		"new",
		"null",
		"package",
		"private",
		"protected",
		"public",
		"return",
		"short",
		"static",
		"strictfp",
		"super",
		"switch",
		"synchronized",
		"this",
		"throw",
		"throws",
		"transient",
		"try",
		"void",
		"volatile",
		"while",
		"true",
		"false",
	}

	for _, keyword in ipairs(java_keywords) do
		if name:lower() == keyword then
			return false, "Name cannot be a Java keyword: " .. keyword
		end
	end

	return true
end

function utils.get_path_dir(path)
	if path == nil or path == "" then
		return nil
	end

	-- Make path absolute
	local abs_path = vim.fn.fnamemodify(path, ":p")

	-- Check if it's a directory
	if vim.fn.isdirectory(abs_path) == 1 then
		return abs_path -- keep directory as-is
	else
		-- It's a file, return parent directory
		return vim.fn.fnamemodify(abs_path, ":h")
	end
end

-- Gets the current directory in an intelligent way.
-- If the user is focused in neo-tree then it retuns the path to the current directory that is selected there.
-- Otherwise, if the user is editing a file then it uses the current diretory of that file.
-- If neither of those work then it returns vim.fn.getcwd()
--- @return string
local function get_current_directory()
	local buf = vim.api.nvim_get_current_buf()

	if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
		local file_type = vim.bo[buf].filetype

		if file_type == "neo-tree" then
			local state = require("neo-tree.sources.manager").get_state("filesystem")
			local node = state.tree:get_node()
			local path = node:get_id()

			local dir = utils.get_path_dir(path)

			if dir then
				return dir
			end
		end

		if file_type == "oil" then
			local filepath = vim.api.nvim_buf_get_name(buf)
			local prefix = "oil://"

			if filepath:sub(1, #prefix) == prefix then
				return vim.fn.fnamemodify(filepath:sub(#prefix + 1), ":p:h")
			end

			print("Expected " .. prefix .. " for oil buffer location - ignoring")
			return vim.fn.getcwd()
		end

		local buffer_type = vim.bo[buf].buftype

		if buffer_type == "" then
			local filepath = vim.api.nvim_buf_get_name(buf)

			return vim.fn.fnamemodify(filepath, ":p:h")
		end
	end

	return vim.fn.getcwd()
end

--- @param str string
--- @param ending string
--- @return boolean
function string.ends_with(str, ending)
	return ending == "" or str:sub(-#ending) == ending
end

-- Tries to find the source directory and package name using the registered patterns for the supplied path
--- @param path string
--- @return string | nil source_dir_path
--- @return string | nil package_name
local function determine_source_directory_and_package_from_path(path)
	for _, pattern in ipairs(M.config.options.src_patterns) do
		local _, end_index = path:find("/" .. pattern .. "/")

		if end_index then
			local package_name = path:sub(end_index + 1):gsub("/", ".")

			return path, package_name
		elseif path:ends_with("/" .. pattern) then
			return path, ""
		end
	end

	return nil
end

---@param java_source_code string
---@return string | nil
local function get_package_from_java_source_code(java_source_code)
	return java_source_code:match("package%s+([^;]+);")
end

--- @param buffer_id integer
--- @return string | nil source_dir_path
--- @return string | nil package_name
local function determine_source_directory_and_package_from_buffer(buffer_id)
	local path = vim.api.nvim_buf_get_name(buffer_id)

	if not path:ends_with(".java") then
		return nil
	end

	local lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, true)

	for _, line in ipairs(lines) do
		local package_name = get_package_from_java_source_code(line)

		if package_name then
			local buffer_dir = vim.fn.fnamemodify(path, ":p:h")

			return buffer_dir, package_name
		end
	end
end

--- @return string source_dir_path
--- @return string package_name
local function determine_source_directory_and_package()
	local current_dir = get_current_directory()

	local source_dir, package_name = determine_source_directory_and_package_from_path(current_dir)

	if source_dir and package_name then
		return source_dir, package_name
	end

	local current_buffer = vim.api.nvim_get_current_buf()

	source_dir, package_name = determine_source_directory_and_package_from_buffer(current_buffer)

	if source_dir and package_name then
		return source_dir, package_name
	end

	return current_dir, ""
end

---
--- Extracts the package declaration from a Java file.
---
---@param file string The path to the Java file.
---@return string|nil The package name or nil if not found.
function utils.extract_package_from_file(file)
	local content = utils.read_file(file)

	if content then
		return get_package_from_java_source_code(content)
	end

	return nil
end

---
--- Reads the entire content of a file.
---
---@param file string The path to the file.
---@return string|nil The file content or nil on failure.
function utils.read_file(file)
	local f = io.open(file, "r")
	if not f then
		return nil
	end
	local content = f:read("*all")
	f:close()
	return content
end

---
--- Generates the content for a new Java file from a template.
---
---@param java_type string The type of Java file.
---@param package string The package name.
---@param name string The class/interface/enum name.
---@return string|nil, string|nil The file content, or nil and an error message.
function utils.generate_file_content(java_type, package, name)
	local template = M.config.templates[java_type]
	if not template then
		return nil, "Template not found for type: " .. java_type
	end

	-- Generate base content without package first
	local base_content = string.format(template, "", name):gsub("package ;\n\n", "")

	-- Build the package line (only if specified)
	local package_line = ""
	if package and package ~= "" then
		package_line = "package " .. package .. ";\n\n"
	end

	-- Handle record template separately for proper formatting
	if java_type == "record" then
		return string.format(
			[[%s%spublic record %s() {
    
}]],
			package_line,
			name
		)
	end

	-- Combine all parts
	return package_line .. base_content
end

local input = {}

---
--- Prompts the user to select a Java type.
---
---@param callback function The function to call with the selected type.
function input.get_java_type(callback)
	local types = { "class", "interface", "enum", "record", "abstract_class" }
	local type_labels = {
		class = "Class",
		interface = "Interface",
		enum = "Enum",
		record = "Record",
		abstract_class = "Abstract Class",
	}

	vim.ui.select(types, {
		prompt = "Select Java type:",
		format_item = function(item)
			return type_labels[item] or item
		end,
	}, callback)
end

---
--- Prompts the user for a string input.
---
---@param prompt string The prompt message.
---@param default string|nil The default value.
---@param callback function The function to call with the user's input.
function input.get_string(prompt, default, callback)
	vim.ui.input({
		prompt = prompt,
		default = default or "",
	}, callback)
end

---
--- Creates the Java file after validating inputs.
---
---@param java_type string The type of Java file.
---@param name string The class/interface/enum name.
---@param package string The package name.
function M.create_java_file(java_type, name, source_dir, package)
	local valid, err = utils.validate_java_name(name)
	if not valid then
		utils.error("Invalid name: " .. err)
		return
	end

	local file_path = source_dir .. "/" .. name .. ".java"
	if vim.fn.filereadable(file_path) == 1 then
		utils.error("File already exists: " .. file_path)
		return
	end

	local content, err_msg = utils.generate_file_content(java_type, package, name)
	if not content then
		utils.error("Error generating content: " .. err_msg)
		return
	end

	local file = io.open(file_path, "w")
	if not file then
		utils.error("Could not create file: " .. file_path)
		return
	end

	file:write(content)
	file:close()

	if M.config.options.auto_open then
		vim.cmd("edit " .. file_path)
	end

	utils.info(string.format("Created %s: %s", java_type, file_path))
end

---
--- Main interactive function to create a new Java file.
--- It guides the user through selecting type, name, and package.
---
function M.java_new()
	input.get_java_type(function(java_type)
		if not java_type then
			utils.info("Java file creation canceled.")
			return
		end

		M.create_java_type_direct(java_type)
	end)
end

---
--- Creates a specific Java type directly, asking only for name and package.
---
---@param java_type string The type of file to create (e.g., 'class').
function M.create_java_type_direct(java_type)
	input.get_string("Name for " .. java_type .. ": ", "", function(name)
		if not name or name == "" then
			utils.error("Name is required.")
			return
		end

		local source_dir, package_name = determine_source_directory_and_package()

		M.create_java_file(java_type, name, source_dir, package_name)
	end)
end

--- Shortcut function to create a Java class.
function M.java_class()
	M.create_java_type_direct("class")
end

--- Shortcut function to create a Java interface.
function M.java_interface()
	M.create_java_type_direct("interface")
end

--- Shortcut function to create a Java enum.
function M.java_enum()
	M.create_java_type_direct("enum")
end

--- Shortcut function to create a Java record.
function M.java_record()
	M.create_java_type_direct("record")
end

---
--- Sets up the plugin, commands, and keymaps.
--- This is the main entry point for the user's configuration.
---
---@param opts table|nil User-provided configuration to override defaults.
function M.setup(opts)
	opts = opts or {}
	M.config = vim.tbl_deep_extend("force", M.config, opts)

	vim.api.nvim_create_user_command("JavaNew", M.java_new, { desc = "Create a new Java file interactively" })
	vim.api.nvim_create_user_command("JavaClass", M.java_class, { desc = "Create a new Java class" })
	vim.api.nvim_create_user_command("JavaInterface", M.java_interface, { desc = "Create a new Java interface" })
	vim.api.nvim_create_user_command("JavaEnum", M.java_enum, { desc = "Create a new Java enum" })
	vim.api.nvim_create_user_command("JavaRecord", M.java_record, { desc = "Create a new Java record" })

	if M.config.keymaps then
		local command_map = {
			java_new = "JavaNew",
			java_class = "JavaClass",
			java_interface = "JavaInterface",
			java_enum = "JavaEnum",
			java_record = "JavaRecord",
		}

		for cmd, keymap in pairs(M.config.keymaps) do
			if keymap and keymap ~= "" and command_map[cmd] then
				vim.keymap.set("n", keymap, "<cmd>" .. command_map[cmd] .. "<cr>", {
					desc = "Java Creator: " .. command_map[cmd],
				})
			end
		end
	end

	utils.info("Java Creator plugin loaded")
end

return M
