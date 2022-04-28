extends Node

enum {
	LOBBY,
	GAME
}

sync var game_state = LOBBY

var network = NetworkedMultiplayerENet.new()
var port = ServerData.port
var max_players = ServerData.max_players

var min_players = 1 #2

var loadins = 0

var update_timer = 0
var update_delay = 5

var game_start_timer = 0
var game_start_delay = 5
var game_start = false

func _ready():
	start_server()
	print("Server launching...")

func _process(delta):
	# Console update timer
	if update_timer >= update_delay:
		update_timer = 0
		_update()
	else:
		update_timer+=delta
	
	# Game startup timer
	if game_start_timer > 0:
		game_start_timer -= delta
		returnStartGame(false, game_start_timer)
	else:
		if game_start == true:
			returnStartGame(true)
			game_start = false
		game_start_timer = 0
		
	# Server-side checks
	if ServerData.players.size() < min_players:
		if game_state != LOBBY: 
			changeGameState(LOBBY)

func _update():
	if OS.get_name() != "Windows":
		clear_console()

	print("Player Count: "+str(ServerData.players.size()))
	print(ServerData.players)

func clear_console():
#https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797
	var escape = PoolByteArray([0x1b]).get_string_from_ascii()
	print(escape + "[2J")	# Clear the console
	print(escape + "[H")	# Set the console cursor position to (0, 0)
	
func start_server():
	network.create_server(port, max_players)
	get_tree().set_network_peer(network)
	print("Server Started!")

	network.connect("peer_connected", self, "_peer_connected")
	network.connect("peer_disconnected", self, "_peer_disconnected")

# Player disconnect/connect
func _peer_connected(player_id):
	print("Player "+str(player_id)+" Connected")
	pushGameState()

func _peer_disconnected(player_id):
	print("Player "+str(player_id)+" Disconnected")
	var players = ServerData.players
	if ServerData.players.size() > 0:
		if ServerData.players.keys().find(player_id) != -1:
			for player in ServerData.players.keys():
				if ServerData.players[player].order > ServerData.players[player_id].order:
					ServerData.players[player].order -= 1
			ServerData.players.erase(player_id)
	
	pushPlayerData()
	pushGameState()
	rpc("serverUpdate")

# Methods
func constructPlayer(player_id, color = Color(1, 1, 1, 0.25).to_html(), title = "???", mode = "egg"):
	ServerData.players[player_id] = {
		"color": color,
		"title": title,
		"mode": mode,
		"loading": false,
		"order": ServerData.players.keys().size()
	}
	pushPlayerData()

remote func fetchLobbyJoin(color, title):
	var player_id = get_tree().get_rpc_sender_id()
	
	if title == "":
		title = str(player_id)
	
	if fetchColorAvailable(color):
		constructPlayer(player_id, color, title)
		rpc_id(player_id, "returnLobbyJoin", color, title)
	else:
		rpc_id(player_id, "Error", "color_taken")

remote func fetchColorAvailable(color, requester = null):
	var player_id = get_tree().get_rpc_sender_id()
	var value = true
	
	for i in ServerData.players.keys():
		if ServerData.players[i].color == color:
			value = false
			break
		else:
			value = true
	
	if requester != null:
		rpc_id(player_id, "returnColorAvailable", requester, color, value)
	else:
		return value

# Syncing
remote func finishLoading():
	var player_id = get_tree().get_rpc_sender_id()

	pushPlayerData()
	rpc_id(player_id, "serverUpdate")

# Player settings
func pushPlayerData():
	rset("players", to_json(ServerData.players))
	rpc("serverUpdate")

func pushGameState():
	rset("game_state", game_state)

# Game states
func changeGameState(state):
	print("Game state changed to: "+str(state))
	game_state = state

# Start game
remote func requestStartGame():
	var player_id = get_tree().get_rpc_sender_id()
	
	# Check if the request is coming from the host
	if ServerData.players[player_id].order == 0:
		print("requestStartGame")
		# Start or cancel the game
		if game_start_timer > 0:
			print("Host cancelled the game")
			game_start = false
			game_start_timer = 0
			returnStartGame(false, -1)
		else:
			# Check if there is the minimum number of players
			if ServerData.players.keys().size() >= min_players:
				print("Host started the game")
				game_start = true
				game_start_timer = game_start_delay

func returnStartGame(launch, timer = 0):
	if launch:
		rpc("returnStartGame", launch, timer)
		changeGameState(GAME)
		pushGameState()
	else:
		rpc_unreliable("returnStartGame", launch, timer)
