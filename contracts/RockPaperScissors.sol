//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract RockPaperScissors is Ownable, ReentrancyGuard {
    // Modifier: playerHasMadeAChoice
    modifier playerHasMadeAChoice(Player memory player) {
        require(
            player.choice != Choice.NOCHOICE,
            string(
                abi.encodePacked(player.name, " needs to make a choice first.")
            )
        );
        _;
    }

    // Modifier: playerIsActive
    modifier playerIsActive(address playerAddress) {
        require(players[playerAddress].active, "Player needs to be active.");
        _;
    }

    // Modifier: playerIsInactive
    modifier playerIsInactive(address playerAddress) {
        require(!players[playerAddress].active, "Player needs to be inactive.");
        _;
    }

    // Modifier: playerIsEnrolled
    modifier playerIsEnrolled() {
        require(players[msg.sender].enrolled, "You are not enrolled.");
        _;
    }

    // Modifier: playerIsNotEnrolled
    modifier playerIsNotEnrolled() {
        require(!players[msg.sender].enrolled, "You are already enrolled.");
        _;
    }

    // Modifier: notInBlacklist
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

    // Modifier: notAnOpponent
    modifier notAnOpponent(address opponent) {
        Opponent[] storage opponentList = players[msg.sender].opponents;
        for (uint256 i = 0; i < opponentList.length; i++) {
            if (opponent == opponentList[i].opponent)
                revert("Already an opponent.");
        }
        _;
    }

    // Modifier: checkBalance
    modifier checkBalance(uint256 newBet) {
        uint256 balance = players[msg.sender].balance;
        uint256 totalBet = players[msg.sender].totalBet;
        uint256 surplus = balance - totalBet;
        require(surplus - newBet >= 0, "Not enough balance");
        _;
    }

    // Token contract instance
    IERC20 public tokenContract;

    // Define Choices enum
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
        nonReentrant
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
        for (uint256 i = 0; players[msg.sender].opponents.length; i++) {
            if (opponent == players[msg.sender].opponents[i].opponent) {
                return players[msg.sender].opponents[i].choice;
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
        notAnOpponent(opponentAddress)
        notInBlacklist(opponentAddress)
    {
        Player storage player = players[msg.sender];
        Player storage opponent = players[opponentAddress];
        player.totalBet += bet;
        player.opponents.push(
            Opponent({ choice: choice, bet: bet, opponent: opponentAddress })
        );
        opponent.opponents.push(
            Opponent({ choice: Choice.NOCHOICE, bet: 0, opponent: msg.sender })
        );
    }

    function getOpponentsAddresses()
        public
        view
        playerIsEnrolled(msg.sender)
        returns (string memory)
    {
        Opponent[] storage opponents = players[msg.sender].opponents;
        bytes memory opponentAddresses = new bytes();
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
        playerHasMadeAChoice(players[player1])
        playerHasMadeAChoice(players[player2])
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
