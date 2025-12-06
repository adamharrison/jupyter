--mod-version:4

local core = require "core"
local DocView = require "core.docview"
local Doc = require "core.doc"
local RootView = require "core.rootview"
local command = require "core.command"
local View = require "core.view"
local syntax = require "core.syntax"
local style = require "core.style"
local Object = require "core.object"
local config = require "core.config"
local common = require "core.common"
local keymap = require "core.keymap"
local ime = require "core.ime"
local litemark = require "plugins.litemark"
local ToolbarView = require "plugins.toolbarview"
local json = require "libraries.json"
local image = require "libraries.image"


-- litemark extensions for jupyter

local Jupyter = {}

local JupyterView = View:extend()
function JupyterView:__tostring() return "JupyterView" end

Jupyter.view = JupyterView

local Block = DocView:extend()
function Block:__tostring() return "Block" end

function Block:draw_scrollbar() return end
function Block:get_scrollable_size() return self.size.y end

local SyntaxDoc = Doc:extend()
function SyntaxDoc:new(block, syntax_extension, ...)
	self.block = block
	self.syntax = syntax.get(syntax_extension)
	SyntaxDoc.super.new(self, ...)
end

function SyntaxDoc:reset_syntax() end
function SyntaxDoc:save(...)
	return self.block.jupyter:save(...)
end

config.plugins.jupyter = common.merge({
  debug = false,
  -- should be python, due to, as you guessed it, windows.
  python = { "python" },
  kernel_timeout = 5,
  matplotlib_inline = true,
  kernel_path = USERDIR .. PATHSEP .. "plugins" .. PATHSEP ..  "jupyter" .. PATHSEP .. "kernel.py",
  output_colors = {
		[0] = style.syntax["normal"],
		[30] = { 0, 0, 0 },
		[31] = { 170, 0, 0 },
		[32] = { 0, 170, 0 },
		[33] = { 170, 85, 0 },
		[34] = { 0, 0, 170 },
		[35] = { 170, 0, 170 },
		[36] = { 0, 170, 170 },
		[37] = { 170, 170, 170 },
		[90] = { 85, 85, 85 },
		[91] = { 255, 85, 85 },
		[92] = { 85, 255, 85 },
		[93] = { 255, 255, 85 },
		[94] = { 85, 85, 255 },
		[95] = { 255, 85, 255 },
		[96] = { 85, 255, 255 },
		[97] = { 255, 255, 255 }
	}
}, config.plugins.jupyter)

function Block:get_height()
  return #self.doc.lines * self:get_line_height()
end

local OutputView = Block:extend()
local InputBlock = Block:extend()

local BlockQuickMenu = ToolbarView:extend()
function BlockQuickMenu:new()
	BlockQuickMenu.super.new(self)
  self.toolbar_font = style.icon_big_font:copy(16)
  self.toolbar_commands = {}
end
function BlockQuickMenu:draw_background() 
	BlockQuickMenu.super.draw_background(self, { common.color "#ffffff70" })
end

function InputBlock:new(...)
	InputBlock.super.new(self,  ...)
	self.quick_menu = BlockQuickMenu()
	self.quick_menu.input_view = self
end


function InputBlock:draw()
	InputBlock.super.draw(self)
	self.quick_menu:draw()
end

function InputBlock:update()
	InputBlock.super.update(self)
	local w = self.quick_menu:get_min_width()
	self.quick_menu.position.x = self.position.x + self.size.x - w
	self.quick_menu.position.y = self.position.y - style.padding.y
	self.quick_menu.size.y = self.quick_menu.toolbar_font:get_height() + style.padding.y * 2
	self.quick_menu.size.x = w
	self.quick_menu:update()
	if self.hovering_quick_menu then
		core.request_cursor("arrow")
	end
end

function InputBlock:on_mouse_moved(x, y, ...)
	if x >= self.quick_menu.position.x and x < self.quick_menu.position.x + self.quick_menu.size.x and y >= self.quick_menu.position.y and y < self.quick_menu.position.y + self.quick_menu.size.y then
		self.hovering_quick_menu = self.quick_menu
		return self.quick_menu:on_mouse_moved(x, y, ...)
	else
		self.hovering_quick_menu = nil
	end
	return InputBlock.super.on_mouse_moved(self, x, y, ...)
end

function InputBlock:on_mouse_pressed(button, x, y, ...)
	if x >= self.quick_menu.position.x and x < self.quick_menu.position.x + self.quick_menu.size.x and y >= self.quick_menu.position.y and y < self.quick_menu.position.y + self.quick_menu.size.y then
		return self.quick_menu:on_mouse_pressed(button, x, y, ...)
	end
	return InputBlock.super.on_mouse_pressed(self, button, x, y, ...)
end

function InputBlock:on_mouse_released(button, x, y, ...)
	if x >= self.quick_menu.position.x and x < self.quick_menu.position.x + self.quick_menu.size.x and y >= self.quick_menu.position.y and y < self.quick_menu.position.y + self.quick_menu.size.y then
		return self.quick_menu:on_mouse_released(button, x, y, ...)
	end
	return InputBlock.super.on_mouse_released(self, button, x, y, ...)
end

local MarkdownBlock = InputBlock:extend()

function OutputView:new(jupyter, doc)
  OutputView.super.new(self, doc or Doc())
  self.jupyter = jupyter
  self.read_only = true
  self.line_ending_colors = {}
end
function OutputView:draw_line_gutter() end

local function parse_256color_code(code)
	if code < 8 then
		return config.plugins.jupyter.output_colors[30 + code]
	elseif code < 16 then
		return config.plugins.jupyter.output_colors[90 + code]
	elseif code >= 232 then
		local num = (code - 232) * 16
		return { num, num, num }
	else
		local num = (code - 16)
		return { (num % 6), math.floor(num / 6) % 6, math.floor(num / 36) }
	end
end

function OutputView:tokenize(line)
	local tokens = {}
	local offset = 1
	local text = self.doc.lines[line]
	local len = text:ulen() or #text
	local fgcolor = self.line_ending_colors[line - 1] and self.line_ending_colors[line - 1][1] or config.plugins.jupyter.output_colors[0]
	local bgcolor = self.line_ending_colors[line - 1] and self.line_ending_colors[line - 1][2]
	while offset < len do
		local s, e, code = text:find("\x1B%[([^m]+)m", offset)
		if not s then break end
		local codes = {}
		for num in code:gmatch("([^;]+)") do table.insert(codes, tonumber(num)) end
		common.push_token(tokens, "doc", line, offset, s - 1, { color = fgcolor, background = bgcolor })
		while #codes > 0 do
			if codes[1] == 38 and code[2] == 5 then
				fgcolor = parse_256color_code(codes[3])
				table.remove(codes, 1)
				table.remove(codes, 1)
				table.remove(codes, 1)
			elseif codes[1] == 48 and code[2] == 5 then
				bgcolor = parse_256color_code(codes[3])
				table.remove(codes, 1)
				table.remove(codes, 1)
				table.remove(codes, 1)
			elseif (codes[1] >= 40 and codes[1] <= 49) or (codes[1] >= 100 and codes[1] <= 109) then
				bgcolor = config.plugins.jupyter.output_colors[math.floor(codes[1] - 10)]
				table.remove(codes, 1)
			else
				fgcolor = config.plugins.jupyter.output_colors[math.floor(codes[1])] or config.plugins.jupyter.output_colors[0]
				table.remove(codes, 1)
			end
		end
		offset = e + 1
	end
	common.push_token(tokens, "doc", line, offset, len, { color = fgcolor, background = bgcolor })
	self.line_ending_colors[line] = { fgcolor, bgcolor } 
	return tokens
end

local CodeBlock = InputBlock:extend()
function CodeBlock:__tostring() return "CodeBlock" end

function CodeBlock:new(text)
  CodeBlock.super.new(self, SyntaxDoc(self, ".py"))
  if text then
    self.doc:insert(1, 1, text)
  end
  self.execution_count = nil
  self.doc:reset_syntax()
  self.id = string.format("%08x", math.random(0, 2 ^ 32))
  self.quick_menu.toolbar_commands = {
		{symbol = "p", command = "jupyter:run-block"},
    {symbol = "f", command = "jupyter:toggle-block-type"},
    {symbol = "x", command = "jupyter:remove-block"}
  }
end

-- function Block:get_virtual_line_offset(...)
--   local x, y = Block.super.get_virtual_line_offset(self, ...)
--   return x, y + style.padding.y
-- end


function CodeBlock:get_gutter_width() return style.code_font:get_width(string.format("[%s]", self.execution_count or "")) + style.padding.x * 2 end
function CodeBlock:draw_line_gutter(vline) 
  if vline == 1 then
    common.draw_text(style.code_font, style.text, string.format("[%s]", self.execution_count and self.execution_count or ""), "left", self.position.x + style.padding.x, self.position.y, 0, self:get_line_height())
  end
end

function CodeBlock:run()
  self.jupyter:run(self)
end


local base64 = {}

function base64.makeencoder( s62, s63, spad )
	local encoder = {}
	for b64code, char in pairs{[0]='A','B','C','D','E','F','G','H','I','J',
		'K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y',
		'Z','a','b','c','d','e','f','g','h','i','j','k','l','m','n',
		'o','p','q','r','s','t','u','v','w','x','y','z','0','1','2',
		'3','4','5','6','7','8','9',s62 or '+',s63 or'/',spad or'='} do
		encoder[b64code] = char:byte()
	end
	return encoder
end


local extract = load[[return function( v, from, width )
  return ( v >> from ) & ((1 << width) - 1)
end]]()

function base64.makedecoder( s62, s63, spad )
	local decoder = {}
	for b64code, charcode in pairs( base64.makeencoder( s62, s63, spad )) do
		decoder[charcode] = b64code
	end
	return decoder
end

local char, concat = string.char, table.concat
local DEFAULT_DECODER = base64.makedecoder()
local DEFAULT_ENCODER = base64.makeencoder()

function base64.decode( b64, decoder, usecaching )
	decoder = decoder or DEFAULT_DECODER
	local pattern = '[^%w%+%/%=]'
	if decoder then
		local s62, s63
		for charcode, b64code in pairs( decoder ) do
			if b64code == 62 then s62 = charcode
			elseif b64code == 63 then s63 = charcode
			end
		end
		pattern = ('[^%%w%%%s%%%s%%=]'):format( char(s62), char(s63) )
	end
	b64 = b64:gsub( pattern, '' )
	local cache = usecaching and {}
	local t, k = {}, 1
	local n = #b64
	local padding = b64:sub(-2) == '==' and 2 or b64:sub(-1) == '=' and 1 or 0
	for i = 1, padding > 0 and n-4 or n, 4 do
		local a, b, c, d = b64:byte( i, i+3 )
		local s
		if usecaching then
			local v0 = a*0x1000000 + b*0x10000 + c*0x100 + d
			s = cache[v0]
			if not s then
				local v = decoder[a]*0x40000 + decoder[b]*0x1000 + decoder[c]*0x40 + decoder[d]
				s = char( extract(v,16,8), extract(v,8,8), extract(v,0,8))
				cache[v0] = s
			end
		else
			local v = decoder[a]*0x40000 + decoder[b]*0x1000 + decoder[c]*0x40 + decoder[d]
			s = char( extract(v,16,8), extract(v,8,8), extract(v,0,8))
		end
		t[k] = s
		k = k + 1
	end
	if padding == 1 then
		local a, b, c = b64:byte( n-3, n-1 )
		local v = decoder[a]*0x40000 + decoder[b]*0x1000 + decoder[c]*0x40
		t[k] = char( extract(v,16,8), extract(v,8,8))
	elseif padding == 2 then
		local a, b = b64:byte( n-3, n-2 )
		local v = decoder[a]*0x40000 + decoder[b]*0x1000
		t[k] = char( extract(v,16,8))
	end
	return concat( t )
end

function base64.encode( str, encoder, usecaching )
	encoder = encoder or DEFAULT_ENCODER
	local t, k, n = {}, 1, #str
	local lastn = n % 3
	local cache = {}
	for i = 1, n-lastn, 3 do
		local a, b, c = str:byte( i, i+2 )
		local v = a*0x10000 + b*0x100 + c
		local s
		if usecaching then
			s = cache[v]
			if not s then
				s = char(encoder[extract(v,18,6)], encoder[extract(v,12,6)], encoder[extract(v,6,6)], encoder[extract(v,0,6)])
				cache[v] = s
			end
		else
			s = char(encoder[extract(v,18,6)], encoder[extract(v,12,6)], encoder[extract(v,6,6)], encoder[extract(v,0,6)])
		end
		t[k] = s
		k = k + 1
	end
	if lastn == 2 then
		local a, b = str:byte( n-1, n )
		local v = a*0x10000 + b*0x100
		t[k] = char(encoder[extract(v,18,6)], encoder[extract(v,12,6)], encoder[extract(v,6,6)], encoder[64])
	elseif lastn == 1 then
		local v = str:byte( n )*0x10000
		t[k] = char(encoder[extract(v,18,6)], encoder[extract(v,12,6)], encoder[64], encoder[64])
	end
	return concat( t )
end

litemark.layout.draw_ops["jupyter-formula"] = function(ctx, block)
	ctx.y = ctx.y + litemark.layout.L.RULE_GAP_TOP

  table.insert(ctx.output, {
    type  = litemark.layout.DRAW_MODE.CANVAS,
    x     = litemark.layout.L.HEADER_MARGIN_LEFT,
    y     = ctx.y,
    w     = block.size.x,
    h     = block.size.y,
    canvas = block.canvas
  })
  ctx.y = ctx.y + block.size.y
end

function MarkdownBlock:__tostring() return "MarkdownBlock" end
function MarkdownBlock:new(text)
  MarkdownBlock.super.new(self, SyntaxDoc(self, ".md"))
  if text then
    self.doc:insert(1, 1, text)
  end
  self.doc:reset_syntax()
  self.id = string.format("%08x", math.random(0, 2 ^ 32))
  self.read_view = litemark.NoteReadView(self.doc, "markdown")
  self.read_view.block_rules = common.merge(litemark.parser.default_block_rules, {})
  self.math_image_cache = {}
  self.quick_menu.toolbar_commands = {
    {symbol = "f", command = "jupyter:toggle-block-type"},
    {symbol = "x", command = "jupyter:remove-block"}
  }
  table.insert(self.read_view.block_rules, 1, { "^%$%$", function(state, line, lang, c2, c3, line_idx)
		state.in_fence = "%$%$"
		table.insert(state.blocks, { 
			type  = "jupyter-formula", 
			lines = {}, 
			arg   = nil,
			close = function(blk)
				-- parse formula here, for now, place a blank canvas
				local formula = table.concat(blk.lines, "\n"):gsub("\n", "\\n")
				local codeblock = string.format([[
import matplotlib.pyplot as lxlplt
from IPython.display import Math as lxlmath, Image as lxlimage
from io import BytesIO as lxlbytesio

lxllatex = lxlmath(r"""%s""").data
lxlfig = lxlplt.figure(figsize=(0.01,0.01))
lxlfig.text(0, 0, f"${lxllatex}$")
lxlbuf = lxlbytesio()
lxlfig.savefig(lxlbuf, format="png", bbox_inches="tight", pad_inches=0.1, dpi=200)
lxlplt.close(lxlfig)
lxlbuf.seek(0)
lxlimage(data=lxlbuf.getvalue())
]], formula)
				if self.math_image_cache[formula] then
					local i = self.math_image_cache[formula]
					blk.canvas = canvas.new(i.width, i.height)
					blk.size = { x = i.width, y = i.height }
					blk.canvas:set_pixels(i:save(), 0, 0, i.width, i.height)
				else
					self.jupyter:queue(function()
						local frame = self.jupyter:execute(codeblock)
						if frame and frame.outputs then
							for _, output in ipairs(frame.outputs) do
								if output.data and output.data["image/png"] then
									local i = image.new(base64.decode(output.data["image/png"]))
									self.math_image_cache[formula] = i
									blk.canvas = canvas.new(i.width, i.height)
									blk.size = { x = i.width, y = i.height }
									blk.canvas:set_pixels(i:save(), 0, 0, i.width, i.height)
									self.read_view:update_layout(true)
									break
								end
							end
						end
					end)
					-- placeholder canvas
					blk.size = { x = 60, y = 60 }
					blk.canvas = canvas.new(blk.size.x, blk.size.y)
				end
			end
		})
		return true
  end  })
end
function MarkdownBlock:get_gutter_width() return style.padding.x * 2 end
function MarkdownBlock:draw_line_gutter() end
function MarkdownBlock:update()
  MarkdownBlock.super.update(self)
	self.read_view.position.x = self.position.x
	self.read_view.position.y = self.position.y
	self.read_view.size.x = self.size.x
	self.read_view.size.y = self.size.y
end

function MarkdownBlock:get_height()
	return math.max(self.read_view:get_scrollable_size(), MarkdownBlock.super.get_height(self))
end

function MarkdownBlock:draw()
	if self.root_view.active_view == self or self.root_view.active_view == self.quick_menu then
		MarkdownBlock.super.draw(self)
	else
		self.read_view:draw()
	end
end

local Figure = View:extend()

function Figure:new(jupyter, image)
  Figure.super.new(self)
  self.jupyter = jupyter
  self.image = image
  self.position = { x = 0, y = 0 }
  self.size = { x = image.width, y = image.height }
  self.bytes = image:save()
  self.canvas = canvas.new(self.size.x, self.size.y)
  self.canvas:set_pixels(self.bytes, 0, 0, self.size.x, self.size.y)
end

function Figure:draw()
  renderer.draw_canvas(self.canvas, math.floor(self.position.x), math.floor(self.position.y))
end

function Figure:get_height()
  return self.size.y
end

function Figure:on_context_menu()
	return { items = {
		{ text = "Save Graph", command = "jupyter:save-graph" }
	} }
end

function JupyterView:on_context_menu()	
	return self.hovering_block and self.hovering_block:on_context_menu()
end

function JupyterView:new()
  JupyterView.super.new(self)
  self.blocks = {}
  self.path = nil
  self.scrollable = true
  self.kernel = nil
  self.active_view = nil
  self.abs_filename = nil
  self.run_queue = {}
end

function JupyterView:get_scrollable_size() 
	local total = style.padding.y
	for _, block in ipairs(self.blocks) do
		total = total + block.size.y + style.padding.y * 3
		for _, output in ipairs(block.output_blocks or {}) do
			total = total + output.size.y + style.padding.y
		end
	end
	return total
end

function JupyterView:save(filename, abs_filename)
	if not filename then
		filename = common.basename(self.abs_filename)
		abs_filename = self.abs_filename
	end
	local t = { 
		cells = {}, 
		metadata = { 
			kernelspec = { display_name = "Python 3", langauge = "python", name = "python3" },
			language_info = { 
				codemirror_mode = { name = "ipython", version = 3 },
				file_extension = ".py",
				mimetype = "text/x-python",
				name = "python",
				nbconvert_exporter = "python",
				pygments_lexer = "ipython3",
				version = Jupyter.version
			},	
		},
		nbformat = 4,
		nbformat_minor = 5 
	}
	for i, block in ipairs(self.blocks) do
		local lines = {}
		table.move(block.doc.lines, 1, #block.doc.lines, 1, lines)
		lines[#lines] = lines[#lines]:gsub("\n","")
		if block:is(MarkdownBlock) then
			table.insert(t.cells, { cell_type = "markdown", id = block.id, metadata = {}, source = lines })
		elseif block:is(CodeBlock) then
			local outputs = {}
			for _, output_block in ipairs(block.output_blocks) do
				table.insert(outputs, output_block.frame)
			end
			table.insert(t.cells, { cell_type = "code", execution_count = block.execution_count, id = block.id, metadata = {}, source = lines, outputs = #outputs > 0 and outputs or json.empty_array })
		end
	end
	assert(io.open(abs_filename, "wb")):write(json.encode(t)):close()
	for _, block in ipairs(self.blocks) do
		if block.doc then
			block.doc:clean()
			block.doc.filename = filename
		end
	end
	self.abs_filename = abs_filename
end

local core_open_doc = core.open_doc
function core.open_doc(abs_path, ...)
	if abs_path and abs_path:find("%.ipynb$") then
		local jv = JupyterView()
		jv:load(abs_path)
		return jv
	end
	return core_open_doc(abs_path, ...)
end

local root_open_doc = RootView.open_doc
function RootView:open_doc(doc, ...)
	if doc.is and doc:is(JupyterView) then
		self:get_active_node_default():add_view(doc)
		return doc
	end
	return root_open_doc(self, doc, ...)
end

function CodeBlock:setOutputs(outputs)
	self.output_blocks = {}
	for _, output in ipairs(outputs) do
		if output.output_type == "stream" and output.name == "stdout" then
			if #self.output_blocks == 0 or self.output_blocks[#self.output_blocks]:is(Figure) then
				table.insert(self.output_blocks, OutputView(self.jupyter, Doc()))
				self.output_blocks[#self.output_blocks].doc:remove(1, 1, math.huge, math.huge)
			end
			local text = output.text
			if type(text) == 'table' then
				text = table.concat(text, '')
			end
			self.output_blocks[#self.output_blocks].doc:insert(math.huge, math.huge, text)
			self.output_blocks[#self.output_blocks].frame = output
		elseif (output.output_type == "display_data" or output.output_type == "execute_result") and output.data["image/png"] then
			table.insert(self.output_blocks, Figure(self, image.new(base64.decode(output.data["image/png"]))))
			self.output_blocks[#self.output_blocks].frame = output
		elseif output.output_type == "execute_result" and output.data["text/plain"] then
			if #self.output_blocks == 0 or self.output_blocks[#self.output_blocks]:is(Figure) then
				table.insert(self.output_blocks, OutputView(self.jupyter, Doc()))
				self.output_blocks[#self.output_blocks].doc:remove(1, 1, math.huge, math.huge)
			end
			local plain = output.data["text/plain"]
			if type(plain) == 'table' then
				plain = table.concat(plain, "")
			end
			self.output_blocks[#self.output_blocks].doc:insert(math.huge, math.huge, plain)
			self.output_blocks[#self.output_blocks].frame = output
		end
	end
end


function JupyterView:load(abs_filename)
	local t = json.decode(io.open(abs_filename, "rb"):read("*all"))
	if t.metadata and t.metadata.kernelspec.language and t.metadata.kernelspec.language ~= "python" then
		core.warn("Jupyter: Cannot interpret %s, cannot interppret any other languages than Python.", t.metadata.kernelspec.language)
	end
	self.abs_filename = abs_filename
	for _, cell in ipairs(t.cells or {}) do
		local block
		if cell.cell_type == "markdown" then
			block = self:add_block(MarkdownBlock(table.concat(cell.source, "")))
		elseif cell.cell_type == "code" then
			block = self:add_block(CodeBlock(table.concat(cell.source, "")))
			if cell.outputs then
				block:setOutputs(cell.outputs)
			end
		end
		if block then
			block.id = cell.id
		end
	end
end

function JupyterView:run(block)
  if not self.kernel then
    self:restart()
  end
  local frame = self:execute(block.doc:get_text(1, 1, math.huge, math.huge))
  if frame.outputs then
    block:setOutputs(frame.outputs)
		block.execution_count = frame.execution_count
  elseif frame.error then
    local outputs = { "\x1B[31m" .. frame.error .. "\n" }
		for i, level in ipairs(frame.traceback) do
			table.insert(outputs, level .. "\n")
		end
		block.output_blocks = { OutputView(self, Doc()) }
    block.output_blocks[#block.output_blocks].doc:insert(1, 1, table.concat(outputs, ""))
  end
  core.redraw = true
end

function JupyterView:draw()
  JupyterView.super.draw(self)
  self:draw_background(style.background3)
  local ox, oy = self:get_content_offset()
  local x = ox + style.padding.x
  local y = oy + style.padding.y
  for i, block in ipairs(self.blocks) do
		y = y + style.padding.y
    block.position.x = x
    block.position.y = y
    block.size.x = self.size.x - style.padding.x * 2
    block.size.y = block:get_height()
    if block.position.y + block.size.y >= self.position.y and block.position.y < self.position.y + self.size.y then
			renderer.draw_rect(block.position.x, block.position.y - style.padding.y, block.size.x, style.padding.y, style.background)
			block:draw()
			renderer.draw_rect(block.position.x, block.position.y + block.size.y, block.size.x, style.padding.y, style.background)
			if block == self.active_view then
				renderer.draw_rect(block.position.x, block.position.y - style.padding.y, 1, block.size.y + style.padding.y * 2, style.caret)
			elseif block == self.hovering_block then
				renderer.draw_rect(block.position.x, block.position.y - style.padding.y, 1, block.size.y + style.padding.y * 2, style.dim)
			end
		end
    y = y + block:get_height() + style.padding.y * 2
    if block.output_blocks and #block.output_blocks > 0 then
      for _, output_block in ipairs(block.output_blocks) do
        output_block.position.x = x
        output_block.position.y = y
        if not output_block:is(Figure) then
          output_block.size.x = self.size.x - style.padding.x * 2
          output_block.size.y = output_block:get_height()
        end
        if output_block.position.y + output_block.size.y >= self.position.y and output_block.position.y < self.position.y + self.size.y then
					output_block:draw()
				end
        y = y + output_block:get_height() + style.padding.y
      end
    end
  end
end

function JupyterView:update()
  JupyterView.super.update(self)
  for i,v in ipairs(self.blocks) do
    v:update()
  end
end

function Block:get_name(...) return self.jupyter:get_name(...) end

function JupyterView:is_dirty()
	for _, block in ipairs(self.blocks) do
		if block.doc and block.doc:is_dirty() then
			return true
		end
	end
	return false
end

function JupyterView:get_name()
	if self.abs_filename then
		return string.format("Jupyter Notebook - %s%s", common.basename(self.abs_filename), self:is_dirty() and "*" or "")
	else
		return string.format("Jupyter Notebook - unsaved*")
	end
end

function JupyterView:add_block(block, index)
  if not index then index = #self.blocks + 1 end
  table.insert(self.blocks, index, block)
  block.jupyter = self
  block.doc.filename = self.abs_filename
  core.redraw = true
  return block
end

function JupyterView:remove_block(block)
  core.redraw = true
  for i, sblock in ipairs(self.blocks) do
    if block == sblock then
      table.remove(self.blocks, i)
      if self.active_view == block then
        self:set_active_view(nil)
      end
      return i
    end
  end
end

function JupyterView:set_active_view(view)
  self.active_view = view
  local target = view or self
  if self.root_view.active_view ~= target then
    self.root_view:set_active_view(target)
  end
end

local function create_kernel(wd)
  assert(system.get_file_info(config.plugins.jupyter.kernel_path), string.format("can't find kernel at %s for Jupyter. Please adjust config.plugins.jupyter.kernel_path.", config.plugins.jupyter.kernel_path))
  local t = common.merge(config.plugins.jupyter.python, {})
  table.insert(t, config.plugins.jupyter.kernel_path)
  table.insert(t, wd)
  return process.start(t)
end

function JupyterView:execute(code, options)
	local frame = json.encode(common.merge({ code = code }, options or {}))
	if config.plugins.jupyter.debug then
		print(">", frame)
	end
	self.kernel.stdin:write(frame .. "\n")
	local output = self.kernel.stdout:read("*line")
	if config.plugins.jupyter.debug then
		local stripped = output:gsub("%c", ""):gsub("\\n", "\n")
		print("<", stripped)
	end
	return json.decode(output)
end

function JupyterView:restart()
  if self.kernel then
    core.log("Shutting down Jupyter kernel...")
    self.kernel.stdin:write(json.encode({ action = "shutdown" }) .. "\n")
    if self.kernel:wait() == 0 then
      core.log("Jupyter kernel successfully shutdown.")
    else
      core.log("Jupyter kernel unable to shutdown successfully.")
    end
  end
  self.kernel = create_kernel(self.abs_filename)
  if config.plugins.jupyter.matplotlib_inline then
    self:execute([[
import matplotlib
from IPython import get_ipython
get_ipython().run_line_magic('matplotlib', 'inline')
]], { silent = true })
  end
  if self.abs_filename then
		self:execute([[
import os
os.chdir("""]] .. common.dirname(self.abs_filename):gsub('"""', '') .. [[""")
]], { silent = true })
	end
  core.log("Jupyter kernel started.")
end

function JupyterView:run_all()
  for _, block in ipairs(self.blocks) do
    if block.run then
      block:run()
    end
  end
end

function JupyterView:clear()
  for _, block in ipairs(self.blocks) do
    block.output_blocks = {}
    block.execution_count = nil
  end
end

function JupyterView:step_queue()
  while #self.run_queue > 0 do
    core.try(self.run_queue[1])
    table.remove(self.run_queue, 1)
  end
end

function JupyterView:queue(func)
  table.insert(self.run_queue, func)
  if #self.run_queue == 1 then
    core.add_thread(function()
      self:step_queue()
    end)
  end
end

function JupyterView:on_mouse_pressed(button, x, y, clicks)
  if button == "left" then
    self.holding_left = true
  end
  if self.hovering_block then
    self:set_active_view(self.hovering_block)
    return self.hovering_block:on_mouse_pressed(button, x, y, clicks)
  end
end


function JupyterView:on_mouse_released(button, ...)
  if button == "left" then
    self.holding_left = false
  end
  if self.hovering_block then
    return self.hovering_block:on_mouse_released(button, ...)
  end
  return JupyterView.super.on_mouse_released(self, button, ...)
end

function JupyterView:get_block_overlapping_point(x, y)
  for _, block in ipairs(self.blocks) do
    if x >= block.position.x and x < block.position.x + block.size.x and y >= block.position.y and y < block.position.y + block.size.y then
      return block
    end
    if block.output_blocks then
			for _, output in ipairs(block.output_blocks) do
				if x >= output.position.x and x < output.position.x + output.size.x and y >= output.position.y and y < output.position.y + output.size.y then
					return output
				end
			end
		end
  end  
end

function JupyterView:on_mouse_moved(x, y)
  if not self.holding_left then
    self.hovering_block = self:get_block_overlapping_point(x, y)
  end
  if self.hovering_block then
		self.cursor = self.hovering_block.cursor
    return self.hovering_block:on_mouse_moved(x, y)
  end
	self.cursor = "arrow"
  return JupyterView.super.on_mouse_moved(self, x, y)
end

local function jupyter_pred(view)
  if view == JupyterView then
    return function(rv, options)
      local jupyter_view = rv.active_view:is(JupyterView) and rv.active_view or rv.active_view.jupyter
      return jupyter_view, jupyter_view, options
    end
  end
  return view
end

local function block_pred(root_view, options)
	local block = root_view.active_view
	block = block and ((block.input_view or block.hovering_block or block))
	return block and block:extends(options and options.extends or Block), block
end


core.add_thread(function()
  core.try(function()
    -- check to see if we have python
    local t = common.merge(config.plugins.jupyter.python, {})
    table.insert(t, "--version")
    local test, err = process.start(t)
    local status = test:wait(config.plugins.jupyter.kernel_timeout)
    if status ~= 0 then
      core.error("Jupyter: You don't seem to have python installed at %s (exit: %s), please install python or configure config.plugins.jupyter.python: %s", config.plugins.jupyter.python[1], status or "timeout", test.stderr:read("*all") or "unknown error")
      return
    end
    Jupyter.python_version = test.stdout:read("*line"):match("Python (.*)")
    if not Jupyter.python_version then 
			core.warn("Jupyter: Can't detect python version.")
    end
    
    -- check to see if we can boot a python kernel, and it has ipykernel installed
    local kernel = create_kernel()
    kernel.stdin:close()
    local status, err = pcall(function()
      local status = kernel:wait()
      assert(status == 0, string.format("Jupyter: Unable to start an IPython kernel and matplotlib (exit: %s): %s. Please ensure you have ipykernel installed (pip install ipykernel matplotlib).", status or "timeout", test.stderr:read("*all") or "unknown error"))
    end)
    if not status then
      core.error("%s", err)
      return
    end

    core.log_quiet("Jupyter kernel with python version %s successfully initialized.", Jupyter.python_version or "unknown")
    Jupyter.initialized = true
    
    command.add(nil, {
      ["jupyter:new-notebook"] = function(rv)
        local node = rv:get_active_node_default()
        local jv = JupyterView()
        jv:queue(function() jv:restart() end)
        node:add_view(jv)
      end
    })

    command.add(jupyter_pred(JupyterView), {
      ["jupyter:add-code-block"] = function(jv, options)
        local block = jv:add_block(CodeBlock(options.text))
        jv:set_active_view(block)
        core.redraw = true
      end,
      ["jupyter:add-markdown-block"] = function(jv, options)
        local block = jv:add_block(MarkdownBlock(options.text))
        jv:set_active_view(block)
        core.redraw = true
      end,
      ["jupyter:restart"] = function(jv)
        jv:queue(function() jv:restart() end)
      end,
      ["jupyter:run-all"] = function(jv)
        jv:queue(function() jv:run_all() end)
      end,
      ["jupyter:clear-all-outputs"] = function(jv)
        jv:clear()
      end
    })
    command.add(Figure, {
			["jupyter:save-graph"] = function(figure)
				figure.jupyter.root_view.command_view:enter("Save graph to", {
					text = "graph.png",
					submit = function(text)
						core.try(function()
							figure.image:save(text)
							core.log("Successfully saved graph to %s.", text)
						end)
					end,
					suggest = function (text)
						return common.home_encode_list(common.path_suggest(common.home_expand(text)))
					end
				})

			end
		})

		local toggle_block_switch = function(block)
			if block:is(CodeBlock) then
				block.jupyter:add_block(
						MarkdownBlock(block.doc:get_text(1, 1, math.huge, math.huge)),
						block.jupyter:remove_block(block)
				)
			else
				block.jupyter:add_block(
					CodeBlock(block.doc:get_text(1, 1, math.huge, math.huge)),
					block.jupyter:remove_block(block)
				)
			end
		end

		command.add(block_pred, {
			["jupyter:toggle-block-type"] = function(block)
        toggle_block_switch(block)
      end
		})
    command.add(MarkdownBlock, { ["jupyter:switch-to-code-block"] = toggle_block_switch })
    command.add(function (rv)
			return block_pred(rv, { extends = CodeBlock })
		end, { 
			["jupyter:switch-to-markdown-block"] = toggle_block_switch, 
			["jupyter:run-block"] = function(block)
        block.jupyter:queue(function() block:run() end)
      end
    })

    command.add(block_pred, {
      ["jupyter:deselect"] = function(block)
        block.jupyter:set_active_view(nil)
      end,
      ["jupyter:remove-block"] = function(block)
        block.jupyter:remove_block(block)
      end
    })

    command.perform("jupyter:new-notebook", core.active_window().root_view)
    command.perform("jupyter:add-markdown-block", core.active_window().root_view, { text = "# Heading 1\n\nTest\n\n$$\n\\dot{x}\n$$" })
  end)

  keymap.add {
    ['escape'] = "jupyter:deselect",
    ['f8'] = "jupyter:run-block"
  }
end)

return Jupyter
