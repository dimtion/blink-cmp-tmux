---@class blink-cmp-tmux.Opts
---@field all_panes boolean
---@field capture_history boolean
---@field triggered_only boolean
---@field trigger_chars string[]

---@type blink-cmp-tmux.Opts
local default_opts = {
	all_panes = false,
	capture_history = false,
	triggered_only = false,
	trigger_chars = { "." },
}

---@module "blink.cmp"
---@class blink.cmp.tmuxSource: blink.cmp.Source
---@field opts blink-cmp-tmux.Opts
local tmux = {}

---@param opts blink-cmp-tmux.Opts
---@return blink.cmp.tmuxSource
function tmux.new(opts)
	local self = setmetatable({}, { __index = tmux })

	self.opts = vim.tbl_deep_extend("force", default_opts, opts)

	return self
end

---@return boolean
function tmux:enabled()
	return vim.fn.executable("tmux") == 1 and os.getenv("TMUX") ~= nil
end

---@return string[]
function tmux:get_trigger_characters()
	return self.opts.trigger_chars
end

---@param pane_id string
---@return string
function tmux:get_pane_content(pane_id)
	local cmd = { "tmux", "capture-pane", "-p", "-t", pane_id }

	if self.opts.capture_history then
		table.insert(cmd, "-S-")
	end

	return vim.system(cmd, { text = true }):wait().stdout
end

---@return string[]
function tmux:get_words()
	local words = {}

	vim.iter(self:get_pane_ids()):each(function(id)
		-- match not only full words, but urls, paths, etc.
		vim.iter(string.gmatch(self:get_pane_content(id), "[%w%d_:/.%-~]+")):each(function(word)
			words[word] = true

			-- but also isolate the words from the result
			for sub_word in string.gmatch(word, "[%w%d]+") do
				words[sub_word] = true
			end
		end)
	end)

	return vim.tbl_keys(words)
end

---@return string[]
function tmux:get_pane_ids()
	local ids = {}
	local cmd = { "tmux", "list-panes", "-F", "'#{pane_id}'" }

	if self.opts.all_panes then
		table.insert(cmd, "-a")
	end
	vim.system(cmd, {
		stdout = function(_, data)
			if not data then
				return
			end
			for id in string.gmatch(data, "%%%d+") do
				if os.getenv("TMUX_PANE") ~= id then
					table.insert(ids, id)
				end
			end
		end,
	}):wait()

	return ids
end

---@param context blink.cmp.Context
---@return lsp.CompletionItem[]
function tmux:get_completion_items(context)
	return vim.iter(self:get_words())
		:map(function(word)
			---@type lsp.CompletionItem
			local item = {
				label = word,
				kind = require("blink.cmp.types").CompletionItemKind.Text,
				insertText = word,
			}
			if self.opts.triggered_only then
				item = vim.tbl_deep_extend("force", item, {
					textEdit = {
						newText = word,
						range = {
							start = { line = context.cursor[1] - 1, character = context.bounds.start_col - 2 },
							["end"] = { line = context.cursor[1] - 1, character = context.cursor[2] },
						},
					},
				})
			end
			return item
		end)
		:totable()
end

---@param context blink.cmp.Context
---@param callback fun(items: blink.cmp.CompletionItem[])
function tmux:get_completions(context, callback)
	vim.schedule(function()
		local triggered = not self.opts.triggered_only
			or vim.list_contains(
				self:get_trigger_characters(),
				context.line:sub(context.bounds.start_col - 1, context.bounds.start_col - 1)
			)
		callback({
			items = triggered and self:get_completion_items(context) or {},
			is_incomplete_backward = true,
			is_incomplete_forward = true,
		})
	end)
end

return tmux
