# The Werewolves Game (狼人杀) simple server

The common problem we face when playing Werewolves game is that, often it's hard to gather enough players, and 1 person has to play god, which further reduced 1 player from enjoying the game.

This is a simple web server that can run on a laptop with ruby, and connect from your cell phones to play Werewolves game, so that all the players can enjoy the game itself

This server is still under development, currently only support logic for the first night

# How to Run

## First Time
1. install rvm with ruby 2.1.5 from https://rvm.io/
2. install bundler
```bash
   $ gem install bundler
```
3. install all gems
```bash
$ bundle install
```

## Start the server
$ bundle exec ruby server.rb

## Test command
[create a room](http://localhost:8080/create_room?num_players=11&num_wolves=4&seer=true&witch=true&cupit=true&idiot=true)

[see the room info](http://localhost:8080/0/room_info)

[see player card](http://localhost:8080/0/user_card/2)