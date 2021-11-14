//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";

contract RockPaperScissors is Ownable, ReentrancyGuard, EIP712 {

    /// @dev MakeMove type hash
    bytes32 public constant MAKE_MOVE_TYPEHASH = keccak256("MakeMove(uint8 choice,address opponent,uint256 nonce, uint256 bet)");

    /// @dev Token contract instance
    IERC20 public tokenContract;

    /// @dev Possible choices
    enum Choice {
        NOCHOICE,
        ROCK,
        PAPER,
        SCISSORS
    }

    /// @dev Opponent's address, player choice and bet
    struct Opponent {
        Choice playerChoice;
        uint256 bet;
        address opponent;
    }

    /// @dev Player's info
    struct Player {
        uint256 balance;
        uint256 totalBet;
        string name;
        Opponent[] opponents;
        address[] blacklist;
        bool active;
        bool enrolled;
        uint256 nonce;
    }

    /// @dev Emitted when a new enrolls in the game
    event Enroll(address indexed player);

    /// @dev Emitted when a player is activated
    event Activate(address indexed player);

    /// @dev Emitted when a player is deactivated
    event Deactivate(address indexed player);

    /// @dev Emitted when there's a winner for the match
    event MatchResult(
        address indexed winner, 
        Choice winnerChoice, 
        address indexed loser, 
        Choice loserChoice, 
        uint256 bet);

    /// @dev Emitted when a draw ocurred for the match
    event Draw(address indexed player1, address indexed player2, Choice choice, uint256 bet);

    /// @dev Emitted when a player make a move against another
    event MakeMove(address indexed player, address indexed opponent);

    /// @dev Mapping (playerAddress => playerInfo)
    mapping(address => Player) private players;

    /// @dev List of enrolled players
    address[] public enrolledPlayers;

    /// @dev Player must be active
    modifier playerIsActive(address playerAddress) {
        require(players[playerAddress].active, "Player must be active.");
        _;
    }

    /// @dev Player must not be active
    modifier playerIsInactive(address playerAddress) {
        require(!players[playerAddress].active, "Player must be inactive.");
        _;
    }

    /// @dev Player must be enrolled
    modifier playerIsEnrolled() {
        require(players[msg.sender].enrolled, "You are not enrolled.");
        _;
    }

    /// @dev Player must not be enrolled
    modifier playerIsNotEnrolled() {
        require(!players[msg.sender].enrolled, "You are already enrolled.");
        _;
    }

    /// @dev Both players must not be blacklisted by one another
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

    /// @dev `opponent` should not be an opponent of `msg.sender`
    modifier notOpponent(address opponent) {
        Opponent[] storage opponentList = players[msg.sender].opponents;
        for (uint256 i = 0; i < opponentList.length; i++) {
            if (opponent == opponentList[i].opponent)
                revert("Already an opponent.");
        }
        _;
    }

    /// @dev `opponent` should be an opponent of player
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

    /// @dev `msg.sender` should have a surplus greater than equal to `newBet`
    modifier checkBalance(uint256 newBet) {
        uint256 balance = players[msg.sender].balance;
        uint256 totalBet = players[msg.sender].totalBet;
        uint256 surplus = balance - totalBet;
        require(surplus - newBet >= 0, "Not enough balance");
        _;
    }

    constructor(address tokenContractAddress) EIP712("RockPaperScissors", "1") {
        tokenContract = IERC20(tokenContractAddress);
    }

    function playWithSig(
        uint8 player1V, 
        bytes32 player1S, 
        bytes32 player1R, 
        uint256 player1Nonce,
        uint8 player1Choice,
        address player1Opponent, 
        uint8 player2V,
        bytes32 player2S,
        bytes32 player2R,
        uint256 player2Nonce,
        uint8 player2Choice,
        address player2Opponent,
        uint256 bet) public 
        {

            // Get player 1 typed data hash
            bytes32 player1TypedHash = _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        MAKE_MOVE_TYPEHASH,
                        player1Choice,
                        player1Opponent,
                        player1Nonce,
                        bet
                    )
                )
            );

            // Get player 2 typed data hash
            bytes32 player2TypedHash = _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        MAKE_MOVE_TYPEHASH,
                        player2Choice,
                        player2Opponent,
                        player2Nonce,
                        bet
                    )
                )
            );

            // Get player 1 and player 2 addresses
            address player1Address = ECDSA.recover(player1TypedHash, player1V, player1S, player1R);
            address player2Address = ECDSA.recover(player2TypedHash, player2V, player2S, player2R);

            // Check ECDSA signature validity
             require(player1Address != address(0) || player2Address != address(0), "ECDSA: Invalid Signature");

            // Check if opponents match
            require(player1Address == player2Opponent, "Wrong opponent for player 2.");
            require(player2Address == player1Opponent, "Wrong opponent for player 1.");

            // Get players' structs
            Player storage player1 = players[player1Address];
            Player storage player2 = players[player2Address];

            // Check surplus
            require(player1.balance - player1.totalBet >= bet, "Not enough surplus (player 1).");
            require(player2.balance - player2.totalBet >= bet, "Not enough surplus (player 2).");

            // Check game result
             bool isDraw; address winner; address loser; Choice winnerChoice; Choice loserChoice;
            (isDraw, winner, loser, winnerChoice, loserChoice) = _getWinner(
                player1Address, Choice(player1Choice), player2Address, Choice(player2Choice));

            // Distribute reward/penalty
            if (!isDraw) {
                players[winner].totalBet -= bet;
                players[loser].totalBet -= bet;

                // Distribute reward/penalty
                players[winner].balance += bet;
                players[loser].balance -= bet;

                emit MatchResult(
                    winner, 
                    winnerChoice, 
                    player2Address, 
                    loserChoice, 
                    bet);
            } else {
                emit Draw(player1Address, player2Address, Choice(player1Choice), bet);
            }

        }

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

        emit Enroll(msg.sender);
    }

    function activate() public playerIsEnrolled playerIsInactive(msg.sender) {
        players[msg.sender].active = true;

        emit Activate(msg.sender);
    }

    function deactivate() public playerIsActive(msg.sender) {
        players[msg.sender].active = false;

        emit Deactivate(msg.sender);
    }

    function getContractBalance() public view onlyOwner returns (uint256) {
        return _getContractBalance();
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
        notInBlacklist(opponentAddress)
    {   

        // Check if it's already an opponent
        Opponent storage opponentInfo = _getOpponentInfo(opponentAddress);

        // Check if player made a choice already
        require(opponentInfo.playerChoice != Choice.NOCHOICE, "Choice made for opponent");

        if (opponentInfo.opponent != address(0)) {
            require(bet == opponentInfo.bet, string(abi.encodePacked("Bet must be equal to ", opponentInfo.bet)));
            bool isDraw; address winner; address loser; Choice winnerChoice; Choice loserChoice;
            (isDraw, winner, loser, winnerChoice, loserChoice) = _getWinner(msg.sender, opponentAddress);

            // Update players' opponents
            _resetGameInfoforPlayers(msg.sender, opponentAddress);

            // Distribute reward/penalty
            if (!isDraw) {
                players[winner].totalBet -= bet;
                players[loser].totalBet -= bet;

                // Distribute reward/penalty
                players[winner].balance += bet;
                players[loser].balance -= bet;

                emit MatchResult(winner, winnerChoice, loser, loserChoice, bet);
            } else {
                emit Draw(opponentAddress, msg.sender, Choice(choice), bet);
            }
            
        } else {

            // Player and Opponent structures
            Player storage player = players[msg.sender];
            Player storage opponent = players[opponentAddress];
            player.totalBet += bet;
            player.opponents.push(
                Opponent({
                    playerChoice: Choice(choice),
                    bet: bet,
                    opponent: opponentAddress
            }));
            opponent.opponents.push(
                Opponent({ playerChoice: Choice.NOCHOICE, bet: bet, opponent: msg.sender })
            );

            emit MakeMove(msg.sender, opponentAddress);
        }
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
                _addressToString(opponents[i].opponent)
            );
        }
        return string(opponentAddresses);
    }

    function _getWinner(address player1, Choice player1Choice, address player2, Choice player2Choice)
        internal
        pure
        returns (bool, address, address, Choice, Choice)
    {

        if (player1Choice == player2Choice) return (false, address(0), address(0), player1Choice, player2Choice);

        if (player1Choice == Choice.ROCK) {
            if (player2Choice == Choice.PAPER) {
                return (true, player2, player1, player2Choice, player1Choice);
            }
            if (player2Choice == Choice.SCISSORS) {
                return (true, player1, player2, player1Choice, player2Choice);
            }
        }

        if (player1Choice == Choice.PAPER) {
            if (player2Choice == Choice.ROCK) {
                return (true, player1, player2, player1Choice, player2Choice);
            }
            if (player2Choice == Choice.SCISSORS) {
                return (true, player2, player1, player2Choice, player1Choice);
            }
        }

        if (player1Choice == Choice.SCISSORS) {
            if (player2Choice == Choice.ROCK) {
                return (true, player2, player1, player2Choice, player1Choice);
            }
            if (player2Choice == Choice.PAPER) {
                return (true, player1, player2, player1Choice, player2Choice);
            }
        }
        return (false, address(0), address(0), Choice.NOCHOICE, Choice.NOCHOICE);
    }

    function _getWinner(address player1, address player2)
        internal
        view
        playerIsActive(player1)
        playerIsActive(player2)
        isOpponent(player1, player2)
        returns (bool, address, address, Choice, Choice)
    {
        Choice player1Choice = _getChoice(player1, player2);
        Choice player2Choice = _getChoice(player2, player1);

        if (player1Choice == player2Choice) return (false, address(0), address(0), player1Choice, player2Choice);

        if (player1Choice == Choice.ROCK) {
            if (player2Choice == Choice.PAPER) {
                return (true, player2, player1, player2Choice, player1Choice);
            }
            if (player2Choice == Choice.SCISSORS) {
                return (true, player1, player2, player1Choice, player2Choice);
            }
        }

        if (player1Choice == Choice.PAPER) {
            if (player2Choice == Choice.ROCK) {
                return (true, player1, player2, player1Choice, player2Choice);
            }
            if (player2Choice == Choice.SCISSORS) {
                return (true, player2, player1, player2Choice, player1Choice);
            }
        }

        if (player1Choice == Choice.SCISSORS) {
            if (player2Choice == Choice.ROCK) {
                return (true, player2, player1, player2Choice, player1Choice);
            }
            if (player2Choice == Choice.PAPER) {
                return (true, player1, player2, player1Choice, player2Choice);
            }
        }
        return (false, address(0), address(0), Choice.NOCHOICE, Choice.NOCHOICE);
    }

    function _getContractBalance() internal view returns (uint256) {
        return tokenContract.balanceOf(address(this));
    }

    function _getChoice(address player, address opponent)
        internal
        view
        returns (Choice)
    {
        for (uint256 i = 0; i < players[player].opponents.length; i++) {
            if (opponent == players[player].opponents[i].opponent) {
                return players[player].opponents[i].playerChoice;
            }
        }
        return Choice.NOCHOICE;
    }

    function _isOpponent(address opponent) internal view returns (bool) {
        Opponent[] storage opponentList = players[msg.sender].opponents;
        for (uint256 i = 0; i < opponentList.length; i++) {
            if (opponent == opponentList[i].opponent) {
                return true;
            }
        }
        return false;
    }

    function _getOpponentInfo(address opponent) internal view returns (Opponent storage) {
        Opponent[] storage opponentList = players[msg.sender].opponents;
        for (uint256 i = 0; i < opponentList.length; i++) {
            if (opponent == opponentList[i].opponent) {
                return opponentList[i];
            }
        }
        revert("Opponent not found for player");
    }

    function _resetGameInfoforPlayers(address player1, address player2) internal {
        Opponent[] storage player1Opponents = players[player1].opponents;
        Opponent[] storage player2Opponents = players[player2].opponents;
        bool foundOpponentPlayer1; bool foundOpponentPlayer2;
        for (uint256 i = 0; i < player1Opponents.length; i++) {
            if (player2 == player1Opponents[i].opponent) {
                foundOpponentPlayer1 = true;
                delete player1Opponents[i];
            }
        }
        require(foundOpponentPlayer1, "Player 1 opponent not found.");

        for (uint256 i = 0; i < player2Opponents.length; i++) {
            if (player1 == player2Opponents[i].opponent) {
                foundOpponentPlayer2 = true;
                delete player2Opponents[i];
            }
        }
        require(foundOpponentPlayer2, "Player 2 opponent not found.");
    }

    function _addressToString(address _address) internal pure returns(string memory) {
       bytes32 _bytes = bytes32(uint256(uint160(_address)));
       bytes memory alphabet = "0123456789abcdef";
       bytes memory _string = new bytes(42);
       _string[0] = "0";
       _string[1] = "x";
       for(uint i = 0; i < 20; i++) {
           _string[2+i*2] = alphabet[uint8(_bytes[i + 12] >> 4)];
           _string[3+i*2] = alphabet[uint8(_bytes[i + 12] & 0x0f)];
       }
       return string(_string);
    }
}
