// chess.zig - UCI chess engine

// Written in 2025 by Omne <many-axioms@outlook.com>
// To the extent possible under law, the author(s) have dedicated all copyright and related and neighboring rights to
// this software to the public domain worldwide. This software is distributed without any warranty.
// You should have received a copy of the CC0 Public Domain Dedication along with this software.
// If not, see <http://creativecommons.org/publicdomain/zero/1.0/>.



const std = @import("std");
// created 2024-01-07
pub const version = "prototype (day 2)";



/// silly features (irrelevant to chess)
pub const silly = struct {
	pub const meowstring = "ᓚᘏᗢ ~meow\n";
	pub fn meow() void {
		const stdout = std.io.getStdOut().writer();
		stdout.writeAll(meowstring) catch {};
	}
};



/// utility functions for debugging purposes only
pub const util = struct {
	pub fn printBb(bb: u64) void {
		var rank:u6 = 0;
		while (rank < 8) : (rank += 1) {
			var file:u6 = 8;
			while (file != 0) {
				file -= 1;
				const mask = @as(u64, 1) << (63 - (rank * 8) - file);
				if (bb & mask != 0) {
					std.debug.print("1 ", .{});
				} else {
					std.debug.print("0 ", .{});
				}
			}
			std.debug.print("\n", .{});
		}
	}
};



pub const Board = struct {
	testbb: u64,
	
	// board
	piece_bb: [n_sides][n_pieces]u64,
	side_bb: [n_sides]u64,
	mailbox: [64]Piece,
	// state
	active: Side,
	castling: u4,
	ep_square: u6,
	halfmove: u8,
	fullmove: u16,
	
	pub const n_pieces = 6;
	pub const n_sides = 2;
	pub const Piece = enum {
		king, queen, rook, bishop, knight, pawn
	};
	pub const Side = enum {
		white, black
	};
	
	// TODO: move this to Zig compile-time so it's more clear what we're doing
    pub const king_attacks = blk: {
        var res: [64]u64 = .{0} ** 64;
        for (0..64) |sq| {
            res[sq] = @as(u64, 1) << sq;
            const rank = sq / 8;
            const file = sq % 8;
			// if we're not on the A file add in the move to the left
            if (file > 0) res[sq] |= res[sq] >> 1;
			// if we're not on the H file add in the move to the right
            if (file < 7) res[sq] |= res[sq] << 1;
			// if we're not on the first rank add in the moves forward
            if (rank > 0) res[sq] |= res[sq] >> 8;
			// if we're not on the last rank add in the moves backward
            if (rank < 7) res[sq] |= res[sq] << 8;
			// remove the starting square
            res[sq] ^= @as(u64, 1) << sq;
        }
        break :blk res;
    };
	pub const knight_attacks = [_]u64{
		0x20400, 0x50800, 0xa1100, 0x142200,
		0x284400, 0x508800, 0xa01000, 0x402000,
		0x2040004, 0x5080008, 0xa110011, 0x14220022,
		0x28440044, 0x50880088, 0xa0100010, 0x40200020,
		0x204000402, 0x508000805, 0xa1100110a, 0x1422002214,
		0x2844004428, 0x5088008850, 0xa0100010a0, 0x4020002040,
		0x20400040200, 0x50800080500, 0xa1100110a00, 0x142200221400,
		0x284400442800, 0x508800885000, 0xa0100010a000, 0x402000204000,
		0x2040004020000, 0x5080008050000, 0xa1100110a0000, 0x14220022140000,
		0x28440044280000, 0x50880088500000, 0xa0100010a00000, 0x40200020400000,
		0x204000402000000, 0x508000805000000, 0xa1100110a000000, 0x1422002214000000,
		0x2844004428000000, 0x5088008850000000, 0xa0100010a0000000, 0x4020002040000000,
		0x400040200000000, 0x800080500000000, 0x1100110a00000000, 0x2200221400000000,
		0x4400442800000000, 0x8800885000000000, 0x100010a000000000, 0x2000204000000000,
		0x4020000000000, 0x8050000000000, 0x110a0000000000, 0x22140000000000,
		0x44280000000000, 0x0088500000000000, 0x0010a00000000000, 0x20400000000000
	};
	pub const white_pawn_attacks = [_]u64{
		0x200, 0x500, 0xa00, 0x1400,
		0x2800, 0x5000, 0xa000, 0x4000,
		0x20000, 0x50000, 0xa0000, 0x140000,
		0x280000, 0x500000, 0xa00000, 0x400000,
		0x2000000, 0x5000000, 0xa000000, 0x14000000,
		0x28000000, 0x50000000, 0xa0000000, 0x40000000,
		0x200000000, 0x500000000, 0xa00000000, 0x1400000000,
		0x2800000000, 0x5000000000, 0xa000000000, 0x4000000000,
		0x20000000000, 0x50000000000, 0xa0000000000, 0x140000000000,
		0x280000000000, 0x500000000000, 0xa00000000000, 0x400000000000,
		0x2000000000000, 0x5000000000000, 0xa000000000000, 0x14000000000000,
		0x28000000000000, 0x50000000000000, 0xa0000000000000, 0x40000000000000,
		0x200000000000000, 0x500000000000000, 0xa00000000000000, 0x1400000000000000,
		0x2800000000000000, 0x5000000000000000, 0xa000000000000000, 0x4000000000000000,
		0x0, 0x0, 0x0, 0x0,
		0x0, 0x0, 0x0, 0x0,
	};
	pub const black_pawn_attacks = [_]u64{
		0x0, 0x0, 0x0, 0x0,
		0x0, 0x0, 0x0, 0x0,
		0x2, 0x5, 0xa, 0x14,
		0x28, 0x50, 0xa0, 0x40,
		0x200, 0x500, 0xa00, 0x1400,
		0x2800, 0x5000, 0xa000, 0x4000,
		0x20000, 0x50000, 0xa0000, 0x140000,
		0x280000, 0x500000, 0xa00000, 0x400000,
		0x2000000, 0x5000000, 0xa000000, 0x14000000,
		0x28000000, 0x50000000, 0xa0000000, 0x40000000,
		0x200000000, 0x500000000, 0xa00000000, 0x1400000000,
		0x2800000000, 0x5000000000, 0xa000000000, 0x4000000000,
		0x20000000000, 0x50000000000, 0xa0000000000, 0x140000000000,
		0x280000000000, 0x500000000000, 0xa00000000000, 0x400000000000,
		0x2000000000000, 0x5000000000000, 0xa000000000000, 0x14000000000000,
		0x28000000000000, 0x50000000000000, 0xa0000000000000, 0x40000000000000,
	};
	
	pub const FenParseError = error {
		IncorrectLength,
		MalformedBoard,
		MalformedActive,
		MalformedCastling,
		MalformedEpSquare,
		MalformedHalfmove,
		MalformedFullmove,
	};
	pub fn init(fen: []const u8) FenParseError!Board {
		var parts = std.mem.splitScalar(u8, fen, ' ');
		var ranks = std.mem.splitScalar(u8, pieces.next() orelse return FenParseError.IncorrectLength, '/');
		for (ranks, 0..) |rank, i| {
			
		}
		return FenParseError.IncorrectLength;
	}
	fn show(self: Board) void {
		util.printBb(self.testbb);
	}
};



pub fn main() !void {
	const stdin = std.io.getStdIn().reader();
	const stdout = std.io.getStdOut().writer();
	try stdout.print(
		"\x1b[32mchess\x1b[33m.zig\x1b[31m {s}\x1b[35m by\x1b[34m Omne\x1b[36m <many-axioms@outlook.com>\x1b[0m\n" ++
		"\x1b[1;31mthis is not a usable program\x1b[0m\n"
		, .{version}
	);
	const board = Board.init("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1") catch undefined;
	
	var gpa = std.heap.GeneralPurposeAllocator(.{}){};
	defer _ = gpa.deinit();
	
	while (true) {
		var arena = std.heap.ArenaAllocator.init(gpa.allocator());
		defer arena.deinit();
		
		var line = std.ArrayList(u8).init(arena.allocator());
		stdin.streamUntilDelimiter(line.writer(), '\n', null) catch |err| switch (err) {
			error.EndOfStream => return,
			else => return err,
		};
		
		var args = std.mem.tokenizeScalar(u8, try line.toOwnedSlice(), ' ');
		const arg = args.next() orelse continue;
		
		// standard UCI commands
		
		if (std.mem.eql(u8, arg, "quit")) {
			return;
		}
		
		if (std.mem.eql(u8, arg, "uci")) {
			try stdout.writeAll(
				\\id name chess.zig
				\\id author Omne <many-axioms@outlook.com>
				\\option name Hash type spin default 1 min 1 max 1
				\\option name Threads type spin default 1 min 1 max 1
				\\uciok
				\\
			);
			continue;
		}
		
		if (std.mem.eql(u8, arg, "setoption")) {
			continue;
		}
		
		if (std.mem.eql(u8, arg, "isready")) {
			try stdout.writeAll("readyok\n");
			continue;
		}
		
		// commands specific to chess.zig
		
		if (std.mem.eql(u8, arg, "show")) {
			board.show();
			continue;
		}
		
		if (std.mem.eql(u8, arg, "perft")) {
			board.show();
			std.debug.print("perft is a work in progress\n", .{});
			continue;
		}
		
		if (std.mem.eql(u8, arg, "meow")) {
			silly.meow();
			continue;
		}
		
		try stdout.writeAll("info error invalid command\n");
	}
}
