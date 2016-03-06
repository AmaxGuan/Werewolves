require 'sinatra'
require 'yajl'
require 'pry-byebug'


#game logic
# each move consist of 2 or 3 parts, (who, action, first night or not) concatenated by _

MOVES = [
  :all_close,
  :cupit_open_1st,
  :cupit_connect_1st,
  :cupit_close_1st,
  :all_open_1st,
  :all_checkCouple_1st, # if couple, couple can be displayed on user's screen
  :all_close_1st,
  :wolves_open,
  :wolves_kill,
  :wolves_close,
  :witch_open,
  :witch_rescue,
  :witch_poison,
  :witch_close,
  :prophet_open,
  :prophet_check,
  :prophet_close,
  :all_open,
  :all_compaign_1st,
  :candidates_speak_1st,
  :citizens_vote_1st,
  :all_vote,
  :all_vote_end,
  :dead_lastWords,
].freeze

class Room
  # static hash to store all game status, key is room number, value stores the state for each room,
  # finished games will be removed from the global hash
  @@rooms = {}

  # size of rooms, use hash for rooms, so that finished games could be recycled
  @@size = 0

  attr_reader :id, :gods, :night, :cur_move, :cards, :votes, :users

  def self.get_room(room_id)
    @@rooms[Integer(room_id)]
  end

  def initialize(num_players, num_wolves, gods)
    @id = @@size
    @gods = gods
    @num_players = num_players
    @num_wolves = num_wolves
    @night = 1
    @cur_move = :all_close
    card_shuffler = []
    num_wolves.times {card_shuffler.push(:wolf)}
    card_shuffler += gods
    card_shuffler.push(:villager) while card_shuffler.size < num_players
    card_shuffler.shuffle!
    @cards = (1..num_players).to_a.zip(card_shuffler).to_h
    @users = {}
    (1..num_players).to_a.zip(card_shuffler).each do |uid, card|
      users[uid] = User.create(uid, card, @id)
    end
    @votes = {}
    @@rooms[@@size] = self
    @@size += 1
  end

  def get_user(user_id)
    users[Integer(user_id)]
  end

  def _next_move(cur_move)
    next_index = (MOVES.index(cur_move) + 1) % MOVES.size
    MOVES[next_index]
  end

  def get_next_move
    possible_next = _next_move(@cur_move)
    if @night != 1 then
      possible_next = _next_move(possible_next) while possible_next.to_s.end_with?('1st')
    end
    possible_next
  end

  def go_next_move
    possible_next = get_next_move

    @cur_move = possible_next
    @night += 1 if @cur_move == :all_close
    @cur_move
  end

  def vote(from, to)
    from_user = get_user(from)
    to_user = get_user(to)
    cur_votes = case cur_move
    when :citizens_vote_1st
      @votes[:police_vote] = {} if @votes[:police_vote].nil?
      raise :wrong_action if from_user.is_candidate
      @votes[:police_vote]
    when :all_vote
      @votes[@night] = {} if @votes[@night].nil?
      @votes[@night]
    end
    raise :wrong_action if from_user.is_dead || to_user.is_dead
    raise :wrong_action if from_user.is_dead || to_user.is_dead
    cur_votes[to] = [] if cur_votes[to].nil?
    cur_votes[to].push(from)
  end

  def get_most_voted(votes)
    max_vote = 0
    winners = []
    votes.each do |to, froms|
      sum = 0
      froms.each do |from|
        from_user = get_user(from)
        sum += from_user.is_police ? 2 : 1
      end
      if sum > max_vote then
        max_vote = sum
        winners = [to]
      elsif sum == max_vote then
        winners.push(to)
      end
    end
  end

  def to_h
    {
      :id => @id,
      :num_players => @num_players,
      :num_wolves => @num_wolves,
      :night => @night,
      :cur_move => @cur_move,
      :cards => @cards,
      :votes => @votes
      :users => @users.map(&:to_h)
    }
  end
end

class User
  attr_reader :id, :room, :card, :is_dead, :is_candidate, :is_police, :is_spirit

  def self.create(id, card, room_id)
    case card
    when :villager
      User.new(id, card, room_id)
    when :prophet
      Prophet.new(id, card, room_id)
    end
  end

  def can_vote
    !is_dead && !is_spirit
  end

  def vote(to_id)
    room.vote(id, to_id)
  end

  def kill(uid)
    raise :wrong_action
  end

  def poison(uid)
    raise :wrong_action
  end

  def rescue(uid)
    raise :wrong_action
  end

  def check(uid)
    raise :wrong_action
  end

  def connect(uid1, uid2)
    raise :wrong_action
  end

  def shoot(uid)
    raise :wrong_action
  end

  def to_h
    {
      :id => @id,
      :card => @card,
      :room => @room,
      :is_dead => @is_dead,
      :is_candidate => @is_candidate,
      :is_police => @is_police
    }
  end
protected
  def initialize(id, card, room_id)
    @id = id
    @card = card
    @room = Room.get_room(room_id)
    @is_dead = false
    @is_candidate = false
    @is_police = false
  end
end

class Prophet < User
  attr_reader :checked
  def initialize(id, card, room_id)
    super(id, card, room_id)
    @checked = {}
  end

  def check(uid)
    raise :wrong_action if @room.cur_move != :prophet_check || !@checked[@room.night].nil?
    result = @room.get_user(uid).card == :wolf ? 'BAD' : 'GOOD'
    @checked[@room.night] = {uid => result}
    result
  end
end

class Witch < User

end

class Cupit < User

end

class Hunter < User

end

class Idiot < User

end

#### APIS #####

#TODO: change to post, get for easy testing
get '/create_room' do
  num_players = Integer(params[:num_players])
  num_wolves = Integer(params[:num_wolves])
  gods = []
  [:prophet, :witch, :hunter, :idiot, :cupit].each do |char|
    gods.push(char) if params[char] == "true"
  end
  room = Room.new(num_players, num_wolves, gods)
  "Room created, You Room Number is: #{room.id}"
end

get '/:room_id/room_info' do
  room = Room.get_room(params[:room_id])
  halt 404, 'room not found' if room.nil?
  Yajl::Encoder.encode(room.to_h)
end

get '/:room_id/user_card/:user_id' do
  room = Room.get_room(params[:room_id])
  user_id = Integer(params[:user_id])
  room.cards[user_id].to_s
end

get '/:room_id/cur_move' do
  room = Room.get_room(params[:room_id])
  room.cur_move.to_s
end

#TODO: change to post, get for easy testing
get '/:room_id/god_go_next_action' do
  room = Room.get_room(params[:room_id])
  room.go_next_move.to_s
end

get '/:room_id/take_action/:user_id' do
  room = Room.get_room(params[:room_id])
  user = room.get_user(params[:user_id])

end