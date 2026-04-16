return {
	'nvim-telescope/telescope.nvim',
	autocmd = false, 
	branch = "master",
	opts = {
		-- pickers = {
		-- 	find_files = {
		-- 		theme = "ivy",
		-- 	},
		-- 	live_grep = {
		-- 		theme = "ivy",
		-- 	},
		-- 	buffers = {
		-- 		theme = "ivy",
		-- 	}
		-- },
	},
	keys = {
		{'ff', ":Telescope find_files <CR>",silent = true},
		{'fg', ":Telescope live_grep <CR>",silent = true},
		{'fb', ":Telescope buffers <CR>",silent = true},
		{'fh', ":Telescope help_tags <CR>",silent = true},
		{'tf', ":Telescope lsp_references <CR>",silent = true},


	}

}
