return {

	{
		'voldikss/vim-translator',

		config = function()

		end,
	},
	{
		'echasnovski/mini.indentscope',
		-- event = "VeryLazy",
		config =  function ()
		require('mini.indentscope').setup({ options = { try_as_border = true ,delay = 400} })


	end,
	},
	{
		'echasnovski/mini.pairs',
		event = "InsertEnter",


	},
	{
	    "hrsh7th/nvim-cmp",
	    -- event = "VeryLazy",

	},

	{
		"hrsh7th/cmp-nvim-lsp",
		-- event = "VeryLazy",

	},
	{
		"L3MON4D3/LuaSnip",
		-- follow latest release.
		version = "v2.*", -- Replace <CurrentMajor> by the latest released major (first number of latest release)
		-- install jsregexp (optional!).
		build = "make install_jsregexp"
	},
	{
	    "hrsh7th/cmp-buffer",
	    -- event = "VeryLazy"
	},
	{
		"lukas-reineke/indent-blankline.nvim",
		main = "ibl",
		---@module "ibl"
		---@type ibl.config
		opts = {},
	},
	-- {
	--   "karb94/neoscroll.nvim",
	--   opts = {},
	-- },
	{
		"neovim/nvim-lspconfig", 
		config = function()
			vim.lsp.config('typescript-language-server', {
				 cmd = { 'typescript-language-server', "--stdio"},
				 filetypes = { 'javascript', 'typescript' },
			}) 
			vim.lsp.config('java-language-server', {
				 cmd = { 'jdtls' },
				filetypes = { 'java' },

			}) 
			vim.lsp.config('rust-analyzer', {
				cmd = { 'rust-analyzer' },
				filetypes = { 'rust', 'rs' },
			})
			vim.lsp.config('vala-lang', {
				cmd = { 'vala-language-server' },
				filetypes = { 'vala' },
			})
			vim.lsp.config('gopls', {
				cmd = { 'gopls' },
				filetypes = { 'go' },
			})
			vim.lsp.config('csharp-language-server', {
				cmd = { 'csharp-language-server' },
				filetypes = { 'cs', 'csharp' }
			})
			vim.lsp.config('clang', {
				cmd = { 'clangd', '--background-index' }
			})
			-- vim.filetype.add({
			--   extension = {
			-- 	asm = 'nasm',
			--   },
			-- })
			-- vim.lsp.config('asm-lsp', {
			-- 	cmd = { 'nasm-lsp' },
			-- 	filetypes = { 'nasm', 'asm' },
			-- 	-- 🎨 Adding this block specifically for NASM support
			-- 	initialization_options = {
			-- 		assembler = "nasm"
			-- 	}
			-- })
			vim.lsp.enable({'luals', 'rust-analyzer', 'clangd', 'typescript-language-server', 'pyright', 'java-language-server', 'vala-lang', 'gopls', 'csharp-language-server'})
		end,
	}, 
	{
		"vala-lang/vala.vim"
	},
	-- {
	-- 	'MeanderingProgrammer/render-markdown.nvim',
	-- 	dependencies = { 'nvim-mini/mini.nvim' },            -- if you use the mini.nvim suite
	-- 	-- dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-mini/mini.icons' },        -- if you use standalone mini plugins
	-- 	-- dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
	-- 	---@module 'render-markdown'
	-- 	---@type render.md.UserConfig
	-- 	opts = {},
	-- },
	{
		"nvim-treesitter/nvim-treesitter",
		config = function() 
			require('nvim-treesitter').install { 'rust', 'javascript', 'zig', 'cpp', 'c'}
		end,
	}

}
