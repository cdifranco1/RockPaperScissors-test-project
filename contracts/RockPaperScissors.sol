//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract RockPaperScissors is Ownable, ReentrancyGuard {
    // Modifier: playerIsActive - Check if player is active
    modifier playerIsActive(address playerAddress) {
        require(players[playerAddress].active, "Player needs to be active.");
        _;
    }

    // Modifier: playerIsInactive - Check if player is inactive
    modifier playerIsInactive(address playerAddress) {
        require(!players[playerAddress].active, "Player needs to be inactive.");
        _;
    }

    // Modifier: playerIsEnrolled - Check if player is enrolled
    modifier playerIsEnrolled() {
        require(players[msg.sender].enrolled, "You are not enrolled.");
        _;
    }

    // Modifier: playerIsNotEnrolled - Check if player is not enrolled
    modifier playerIsNotEnrolled() {
        require(!players[msg.sender].enrolled, "You are already enrolled.");
        _;
    }

    // Modifier: notInBlacklist - Check if player is in the opponent's blacklist and vice-versa
    modifier notInBlacklist(address opponent) {
        address[] storage opponentBlacklist = players[opponent].blacklist;
        address[] storage yourBlacklist = players[msg.sender].blacklist;
        for (uint256 i = 0; i < opponentBlacklist.length; i++) {
            if (msg.sender == opponentBlacklist[i])
                revert("You are blacklisted.");
        }
        for (uint256 i = 0; i < yourBlacklist.length; i++) {
            if (opponent == yourBlacklist[i])
                revert("Opponent is blacklisted.");
        }
        _;
    }

    // Modifier: notOpponent - Check if <opponent> is not an opponent of player
    modifier notOpponent(address opponent) {
        Opponent[] storage opponentList = players[msg.sender].opponents;
        for (uint256 i = 0; i < opponentList.length; i++) {
            if (opponent == opponentList[i].opponent)
                revert("Already an opponent.");
        }
        _;
    }

    // Modifier: isOpponent - Check if <opponent> is an opponent of player
    modifier isOpponent(address player, address opponent) {
        Opponent[] storage opponentList = players[player].opponents;
        bool isOpponentFlag = false;
        for (uint256 i = 0; i < opponentList.length; i++) {
            if (opponent == opponentList[i].opponent) {
                isOpponentFlag = true;
                break;
            }
        }
        if (!isOpponentFlag) revert("Not and opponent.");
        _;
    }

    // Modifier: checkBalance - check player balance
    modifier checkBalance(uint256 newBet) {
        uint256 balance = players[msg.sender].balance;
        uint256 totalBet = players[msg.sender].totalBet;
        uint256 surplus = balance - totalBet;
        require(surplus - newBet >= 0, "Not enough balance");
        _;
    }

    // Token contract instance
    IERC20 public tokenContract;

    // Define Choice enum - Possible choices
    enum Choice {
        NOCHOICE,
        ROCK,
        PAPER,
        SCISSORS
    }

    struct Opponent {
        Choice choice;
        uint256 bet;
        address opponent;
    }

    // Define Player struct
    struct Player {
        uint256 balance;
        uint256 totalBet;
        string name;
        Opponent[] opponents;
        address[] blacklist;
        bool active;
        bool enrolled;
    }

    // Define players mapping
    mapping(address => Player) private players;

    // Enrolled players
    address[] public enrolledPlayers;

    constructor(address tokenContractAddress) {
        tokenContract = IERC20(tokenContractAddress);
    }

    // Register new player
    function enroll(string memory name, uint256 numberOfTokens)
        public
        playerIsNotEnrolled
    {
        Player storage newPlayer = players[msg.sender];
        newPlayer.enrolled = true;
        newPlayer.name = name;
        newPlayer.balance = numberOfTokens;
        newPlayer.active = true;
        enrolledPlayers.push(msg.sender);
    }

    function activate() public playerIsEnrolled playerIsInactive(msg.sender) {
        players[msg.sender].active = true;
    }

    function deactivate() public playerIsActive(msg.sender) {
        players[msg.sender].active = false;
    }

    function getContractBalance() public view onlyOwner returns (uint256) {
        return _getContractBalance();
    }

    function _getContractBalance() private view returns (uint256) {
        return tokenContract.balanceOf(address(this));
    }

    function _getChoice(address player, address opponent)
        private
        view
        returns (Choice)
    {
        for (uint256 i = 0; i < players[player].opponents.length; i++) {
            if (opponent == players[player].opponents[i].opponent) {
                return players[player].opponents[i].choice;
            }
        }
        return Choice.NOCHOICE;
    }

    function play(
        uint8 choice,
        address opponentAddress,
        uint256 bet
    )
        public
        checkBalance(bet)
        playerIsActive(msg.sender)
        playerIsActive(opponentAddress)
        notOpponent(opponentAddress)
        notInBlacklist(opponentAddress)
    {
        Player storage player = players[msg.sender];
        Player storage opponent = players[opponentAddress];
        player.totalBet += bet;
        player.opponents.push(
            Opponent({
                choice: Choice(choice),
                bet: bet,
                opponent: opponentAddress
            })
        );
        opponent.opponents.push(
            Opponent({ choice: Choice.NOCHOICE, bet: 0, opponent: msg.sender })
        );
    }

    function getOpponentsAddresses()
        public
        view
        playerIsEnrolled
        returns (string memory)
    {
        Opponent[] storage opponents = players[msg.sender].opponents;
        bytes memory opponentAddresses;
        for (uint256 i = 0; i < opponents.length; i++) {
            opponentAddresses = abi.encodePacked(
                opponentAddresses,
                ",",
                opponents[i].opponent
            );
        }
        return string(opponentAddresses);
    }

    function getWinner(address player1, address player2)
        private
        view
        playerIsActive(player1)
        playerIsActive(player2)
        isOpponent(player1, player2)
        returns (bool, address)
    {
        Choice player1Choice = _getChoice(player1, player2);
        Choice player2Choice = _getChoice(player2, player1);

        if (player1Choice == player2Choice) return (false, address(0));

        if (player1Choice == Choice.ROCK) {
            if (player2Choice == Choice.PAPER) {
                return (true, player2);
            }
            if (player2Choice == Choice.SCISSORS) {
                return (true, player1);
            }
        }

        if (player1Choice == Choice.PAPER) {
            if (player2Choice == Choice.ROCK) {
                return (true, player1);
            }
            if (player2Choice == Choice.SCISSORS) {
                return (true, player2);
            }
        }

        if (player1Choice == Choice.SCISSORS) {
            if (player2Choice == Choice.ROCK) {
                return (true, player2);
            }
            if (player2Choice == Choice.PAPER) {
                return (true, player1);
            }
        }
        return (false, address(0));
    }
}
