package main

import "core:fmt"
import rl "vendor:raylib"
import "core:math/rand"
import "core:math/noise"
import "core:math/linalg"
import "core:strings"

cell_matrix :: [dynamic][dynamic]cell
cell :: struct {
	matter: matter_type,
	matter_state: matter_state_type,
	powder_state: powder_state_type,
}
matter_type :: enum {
	EMPTY,
	WATER,
	EDGE,
	PLAYER,
	WALL,
}
matter_state_type :: enum {
	SOLID,
	POWDER,
}
powder_state_type :: enum {
	ACTIVE,
	STATIC,
}
tools :: enum {
	DIG,
	SOLID,
}

WORLD_SIZE := [2]int{ 640, 640 }
CAM_ZOOM: int = 8
PREGEN_HEIGHT := 320
PREGEN_OFFSET := 5
PLAYER_MOVE_SPEED := 0.5
COLORS := [10]rl.Color {
	rl.Color{ 47, 42, 53, 255 },
	rl.Color{ 68, 61, 56, 255 },
	rl.Color{ 98, 86, 83, 255 },
	rl.Color{ 154, 93, 64, 255 },
	rl.Color{ 169, 129, 67, 255 },
	rl.Color{ 59, 66, 98, 255 },
	rl.Color{ 111, 119, 119, 255 },
	rl.Color{ 152, 157, 160, 255 },
	rl.Color{ 194, 184, 169, 255 },
	rl.Color{ 217, 219, 186, 255 },
}
WALLHACK := false

cam_pos := [2]int{ }
player_cells := [6][2]int{ }
player_move_intent: [2]int
player_act_intent: [2]int
cells := make_cells()
cells_next := make_cells()
player_move_timer := 0
active_tool := tools.DIG

main :: proc() {
	// RENDER SETUP
	using rl
	InitWindow(640, 640, "snowy")
	SetTargetFPS(30)
	player_texture := LoadTexture("./assets/sprites/player/player_1.png")
	
	// LOGIC SETUP
	seed := rand.int63()
	for i in 0..<WORLD_SIZE.x {
		column_height := PREGEN_HEIGHT + int(noise.noise_2d(seed, { f64(i) / 20, 1 }) * f32(PREGEN_OFFSET))
		for j in column_height..<WORLD_SIZE.y {
			switch noise.noise_2d(seed, { f64(i), f64(j) } / 20) {
			case -1.0..<0:
				set_cell(&cells, i, j, make_empty_cell())
			case 0..<0.5:
				set_cell(&cells, i, j, make_cell(matter_type.WATER, matter_state_type.SOLID, powder_state_type.STATIC))
			case:
				set_cell(&cells, i, j, make_cell(matter_type.WATER, matter_state_type.POWDER, powder_state_type.STATIC))
			}
		}
	}
	
	player_cells[0] = { WORLD_SIZE.x / 2, PREGEN_HEIGHT - PREGEN_OFFSET - 3 }
	player_cells[1] = player_cells[0] + { 0, 1 }
	player_cells[2] = player_cells[0] + { 0, 2 }
	player_cells[3] = player_cells[0] + { 1, 0 }
	player_cells[4] = player_cells[0] + { 1, 1 }
	player_cells[5] = player_cells[0] + { 1, 2 }
	for player_cell in player_cells {
		set_cell(&cells, player_cell.x, player_cell.y, make_cell(matter_type.PLAYER, matter_state_type.SOLID, powder_state_type.STATIC))
	}
	cam_pos = player_cells[0]
	
	// GAME LOOP
	for !rl.WindowShouldClose() {
		player_move_intent = { }
		if player_move_timer == 0 {
			if IsKeyDown(KeyboardKey.W) || IsKeyPressed(KeyboardKey.W) {
				player_move_intent.y -= 1
			}
			if IsKeyDown(KeyboardKey.S) || IsKeyPressed(KeyboardKey.S) {
				player_move_intent.y += 1
			}
			if IsKeyDown(KeyboardKey.A) || IsKeyPressed(KeyboardKey.A) {
				player_move_intent.x -= 1
			}
			if IsKeyDown(KeyboardKey.D) || IsKeyPressed(KeyboardKey.D) {
				player_move_intent.x += 1
			}
			player_move_timer = int(1 / PLAYER_MOVE_SPEED)
		} else {
			player_move_timer -= 1
		}
		player_act_intent = { }
		if IsKeyPressed(KeyboardKey.UP) {
			player_act_intent.y -= 1
		}
		if IsKeyPressed(KeyboardKey.DOWN) {
			player_act_intent.y += 1
		}
		if IsKeyPressed(KeyboardKey.LEFT) {
			player_act_intent.x -= 1
		}
		if IsKeyPressed(KeyboardKey.RIGHT) {
			player_act_intent.x += 1
		}
		
		if IsKeyPressed(KeyboardKey.ONE) {
			active_tool = tools.DIG
		}
		if IsKeyPressed(KeyboardKey.TWO) {
			active_tool = tools.SOLID
		}
		
		// set_cell(&cells, rand.int_max(WORLD_SIZE.x), 0, powder.SNOW_ACTIVE)
		process_powder(&cells, &cells_next)
		
		{
			BeginDrawing()
			defer EndDrawing()
			
			ClearBackground(COLORS[1])
			
			screen_borders := [2][2]int{}
			screen_borders.x[0] = cam_pos.x - int(320 / CAM_ZOOM)
			screen_borders.x[1] = cam_pos.x + int(320 / CAM_ZOOM)
			screen_borders.y[0] = cam_pos.y - int(320 / CAM_ZOOM)
			screen_borders.y[1] = cam_pos.y + int(320 / CAM_ZOOM)
			if WALLHACK {
				for i := screen_borders.x[0]; i < screen_borders.x[1]; i += 1 {
					for j := screen_borders.y[0]; j < screen_borders.y[1]; j += 1 {
						curr_cell := get_cell(&cells, i, j)
						if curr_cell.matter != matter_type.EMPTY {
							render_pos := convert_to_screen_pos([2]int{ i, j })
							color: Color
							switch curr_cell.matter {
							case matter_type.WATER:
								switch curr_cell.matter_state {
								case matter_state_type.POWDER:
									color = COLORS[8]
								case matter_state_type.SOLID:
									color = COLORS[7]
								}
							case matter_type.PLAYER:
								color = COLORS[4]
							case matter_type.WALL:
								color = COLORS[6]
							case matter_type.EMPTY, matter_type.EDGE:
							}
							DrawRectangle(i32(render_pos.x), i32(render_pos.y), i32(CAM_ZOOM), i32(CAM_ZOOM), color)
						}
					}
				}
			} else if !WALLHACK {
				cells_to_draw := [dynamic][2]int{ }
				cast_vision :: proc(i, j: int) {
					ray_target := [2]f32{ f32(i), f32(j) }
					ray_direction := linalg.vector_normalize(ray_target - [2]f32{ f32(player_cells[4].x), f32(player_cells[4].y) })
					for step in 0..<(320 / CAM_ZOOM) {
						curr_f := [2]f32{ f32(player_cells[4].x), f32(player_cells[4].y) } + ray_direction * f32(step)
						curr_i := [2]int{ int(curr_f.x), int(curr_f.y)}
						curr_cell := get_cell(&cells, curr_i.x, curr_i.y)
						
						render_pos := convert_to_screen_pos([2]int{ curr_i.x, curr_i.y })
						color: Color
						switch curr_cell.matter {
						case matter_type.WATER:
							switch curr_cell.matter_state {
							case matter_state_type.POWDER:
								color = COLORS[8]
							case matter_state_type.SOLID:
								color = COLORS[7]
							}
						case matter_type.PLAYER:
							color = COLORS[4]
						case matter_type.WALL:
							color = COLORS[6]
						case matter_type.EMPTY:
							color = COLORS[0]
						case matter_type.EDGE:
						}
						DrawRectangle(i32(render_pos.x), i32(render_pos.y), i32(CAM_ZOOM), i32(CAM_ZOOM), color)
						
						if curr_cell.matter != matter_type.PLAYER && curr_cell.matter != matter_type.EMPTY {
							break
						}
					}
				}
				for j := screen_borders.y[0]; j < screen_borders.y[1]; j += 1 {
					for i in screen_borders.x {
						cast_vision(i, j)
					}
				}
				for i := screen_borders.x[0]; i < screen_borders.x[1]; i += 1 {
					for j in screen_borders.y {
						cast_vision(i, j)
					}
				}
			}
			
			fps := 1 / GetFrameTime()
			DrawText(strings.clone_to_cstring(fmt.tprint(int(fps))), 8, 8, 16, COLORS[4])
			
			DrawText(strings.clone_to_cstring(fmt.tprint(active_tool)), 8, 600, 32, COLORS[4])
		}
	}
	
	defer clear(&cells)
	defer clear(&cells_next)
	CloseWindow()
}

make_cells :: proc() -> cell_matrix {
	new_matrix := cell_matrix{ }
	resize(&new_matrix, WORLD_SIZE.x)
	for i := 0; i < WORLD_SIZE.x; i += 1 {
		resize(&new_matrix[i], WORLD_SIZE.y)
	}
	return new_matrix
}

process_powder :: proc(cells: ^cell_matrix, cells_next: ^cell_matrix) {
	for i := 0; i < WORLD_SIZE.x; i += 1 {
		for j := 0; j < WORLD_SIZE.y; j += 1 {
			set_cell(cells_next, i, j, make_empty_cell())
		}
	}
	
	is_player_near_wall := false
	{
		player_pos := player_cells[0]
		for i in -1..=2 {
			if get_cell(cells, player_pos.x - 1, player_pos.y + i).matter_state == matter_state_type.SOLID ||
			get_cell(cells, player_pos.x + 2, player_pos.y + i).matter_state == matter_state_type.SOLID {
				is_player_near_wall = true
			}
		}
	}
	
	if !is_player_near_wall {
		if get_cell(cells, player_cells[2].x, player_cells[2].y + 1).matter == matter_type.EMPTY &&
		get_cell(cells, player_cells[5].x, player_cells[5].y + 1).matter == matter_type.EMPTY {
			move_player({ 0, 1 })
		}
	}
	if player_act_intent != { } {
		for player_cell in player_cells {
			target_pos := player_cell + player_act_intent
			target_cell := get_cell(cells, target_pos.x, target_pos.y)
			switch active_tool {
			case tools.DIG:
				if target_cell.matter_state == matter_state_type.SOLID {
					target_cell.matter_state = matter_state_type.POWDER
					set_cell(cells, target_pos.x, target_pos.y, target_cell)
				} else if target_cell.matter_state == matter_state_type.POWDER {
					set_cell(cells, target_pos.x, target_pos.y, make_empty_cell())
				}
			case tools.SOLID:
				set_cell(cells, target_pos.x, target_pos.y, make_cell(matter_type.WALL, matter_state_type.SOLID, powder_state_type.STATIC))
			}
		}
	} else {
		if is_player_near_wall &&
		player_move_intent.y == -1 &&
		get_cell(cells, player_cells[0].x, player_cells[0].y - 1).matter == matter_type.EMPTY &&
		get_cell(cells, player_cells[0].x + 1, player_cells[0].y - 1).matter == matter_type.EMPTY {
			move_player({ 0, -1 })
		}
		else if is_player_near_wall &&
		player_move_intent.y == 1 &&
		get_cell(cells, player_cells[0].x, player_cells[0].y + 3).matter == matter_type.EMPTY &&
		get_cell(cells, player_cells[0].x + 1, player_cells[0].y + 3).matter == matter_type.EMPTY {
			move_player({ 0, 1 })
		}
		else if player_move_intent.x == -1 {
			if get_cell(cells, player_cells[0].x - 1, player_cells[0].y).matter == matter_type.EMPTY &&
			get_cell(cells, player_cells[1].x - 1, player_cells[1].y).matter == matter_type.EMPTY {
				if get_cell(cells, player_cells[2].x - 1, player_cells[2].y).matter == matter_type.EMPTY {
					move_player({ -1, 0 })
				} else if get_cell(cells, player_cells[0].x - 1, player_cells[0].y - 1).matter == matter_type.EMPTY &&
				get_cell(cells, player_cells[3].x - 1, player_cells[3].y - 1).matter == matter_type.EMPTY {
					move_player({ -1, -1 })
				}
			}
		} else if player_move_intent.x == 1 {
			if get_cell(cells, player_cells[3].x + 1, player_cells[3].y).matter == matter_type.EMPTY &&
			get_cell(cells, player_cells[4].x + 1, player_cells[4].y).matter == matter_type.EMPTY {
				if get_cell(cells, player_cells[5].x + 1, player_cells[5].y).matter == matter_type.EMPTY {
					move_player({ 1, 0 })
				} else if get_cell(cells, player_cells[0].x + 1, player_cells[0].y - 1).matter == matter_type.EMPTY &&
				get_cell(cells, player_cells[3].x + 1, player_cells[3].y - 1).matter == matter_type.EMPTY {
					move_player({ 1, -1 })
				}
			}
		}
	}
	
	for i := 0; i < WORLD_SIZE.x; i += 1 {
		for j := 0; j < WORLD_SIZE.y; j += 1 {
			curr_cell := get_cell(cells, i, j)
			
			switch curr_cell.matter_state {
			case matter_state_type.POWDER:
				switch curr_cell.powder_state {
				case powder_state_type.ACTIVE:
					if get_cell(cells, i, j + 1).matter != matter_type.EMPTY &&
					get_cell(cells, i + 1, j + 1).matter != matter_type.EMPTY &&
					get_cell(cells, i - 1, j + 1).matter != matter_type.EMPTY {
						curr_cell.powder_state = powder_state_type.STATIC
						set_cell(cells_next, i, j, curr_cell)
					} else {
						possible_directions := []string{ "left", "right", "down" }
						direction := rand.choice(possible_directions)
						switch direction {
						case "left":
							if get_cell(cells, i - 1, j).matter != matter_type.EMPTY ||
							get_cell(cells_next, i - 1, j).matter != matter_type.EMPTY {
								set_cell(cells_next, i, j, curr_cell)
							} else {
								set_cell(cells_next, i - 1, j, curr_cell)
							}
						case "right":
							if get_cell(cells, i + 1, j).matter != matter_type.EMPTY ||
							get_cell(cells_next, i + 1, j).matter != matter_type.EMPTY {
								set_cell(cells_next, i, j, curr_cell)
							} else {
								set_cell(cells_next, i + 1, j, curr_cell)
							}
						case "down":
							if get_cell(cells, i, j + 1).matter != matter_type.EMPTY ||
							get_cell(cells_next, i, j + 1).matter != matter_type.EMPTY {
								set_cell(cells_next, i, j, curr_cell)
							} else {
								set_cell(cells_next, i, j + 1, curr_cell)
							}
						}
					}
				case powder_state_type.STATIC:
					if get_cell(cells, i, j + 1).matter != matter_type.EMPTY &&
					get_cell(cells, i + 1, j + 1).matter != matter_type.EMPTY &&
					get_cell(cells, i - 1, j + 1).matter != matter_type.EMPTY {
						set_cell(cells_next, i, j, curr_cell)
					} else {
						curr_cell.powder_state = powder_state_type.ACTIVE
						set_cell(cells_next, i, j, curr_cell)
					}
				}
			case matter_state_type.SOLID:
				set_cell(cells_next, i, j, curr_cell)
			}
		}
	}
	
	for i := 0; i < WORLD_SIZE.x; i += 1 {
		for j := 0; j < WORLD_SIZE.y; j += 1 {
			set_cell(cells, i, j, get_cell(cells_next, i, j))
		}
	}
}

convert_to_screen_pos :: proc(global_pos: [2]int) -> [2]int {
	return (global_pos - { cam_pos.x, cam_pos.y }) * CAM_ZOOM + [2]int{ 320, 320 }
}

move_player :: proc(move_vec: [2]int) {
	for &player_cell in player_cells {
		set_cell(&cells, player_cell.x, player_cell.y, make_empty_cell())
	}
	for &player_cell in player_cells {
		player_cell += move_vec
		set_cell(&cells, player_cell.x, player_cell.y, make_cell(matter_type.PLAYER, matter_state_type.SOLID, powder_state_type.STATIC))
	}
	cam_pos = player_cells[0]
}

get_cell :: proc(target_cells: ^cell_matrix, x, y: int) -> cell {
	if y >= WORLD_SIZE.y || y < 0 || x >= WORLD_SIZE.x || x < 0 {
		return make_cell(matter_type.EDGE, matter_state_type.SOLID, powder_state_type.STATIC)
	} else {
		return target_cells[x][y]
	}
}

set_cell :: proc(target_cells: ^cell_matrix, x, y: int, value: cell) {
	if y >= 0 && y < WORLD_SIZE.y || x >= WORLD_SIZE.x || x < 0 {
		target_cells[x][y] = value
	}
}

make_cell :: proc(matter: matter_type, matter_state: matter_state_type, powder_state: powder_state_type) -> cell {
	return cell{ matter, matter_state, powder_state }
}

make_empty_cell :: proc() -> cell {
	return cell{ matter_type.EMPTY, matter_state_type.SOLID, powder_state_type.STATIC }
}
