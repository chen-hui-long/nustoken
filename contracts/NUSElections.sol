// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

import "./NUSToken.sol";

/** 
 * @title NUSElections
 */

 /** 
 * To-do:
 * 1. Use NUSToken once NUSToken contract is ready
 * 2. Events 
 */

contract NUSElections {

    struct Voter {
        uint256 weight; // weight is accumulated by delegation, default is 0
        bool voted;  // if true, that person already voted, default is false 
        // address delegate; // person delegated to
        uint256 vote;   // index of the voted proposal, default is 0
    }

    // NUSToken nusTokenInstance
    NUSToken nusTokenInstance;
    address public electionOwner;
    address[] voterList;
    uint256[] votingOptions;
    uint256[] votingResultsList;
    mapping(address => Voter) voters;
    mapping(uint256 => uint256) votingResults;
    bool electionStatus;
    bool rewardStatus;
    uint256 totalVotes = 0;
    uint256 minimumVoters = 0;
    uint256 votingReward = 1;
    mapping (address => bool) votersRewarded; 

    /** 
     * Create a new election
     * @param options a list of options, always start from index 0. (frontend need to configure it to start from 0)
     */
    constructor(uint256[] memory options, uint256 minVoters, uint reward, NUSToken nusTokenInstanceAddress) public {
        nusTokenInstance = nusTokenInstanceAddress;
        electionOwner = msg.sender;
        votingOptions = options;
        electionStatus = false;
        rewardStatus = false;
        votingResultsList = new uint256[](options.length);
        minimumVoters = minVoters;
        votingReward = reward;
    }

    // events 
    
    // A event that emits the id of the winning vote and the vote count when there is only 1 winner 
    event winningVote(uint256, uint256);
    // A event that emits the vote count when the voting results in a draw
    event draw(uint256);
    // A event that emits the ids of the voting options that result in a draw
    event drawVotes(uint256);
    // A event that emit that no one has voted 
    event  noOneVoted();

    // modifiers 

    modifier electionOngoing() {
        require(
            !electionStatus, 
            "Election has ended."
        );
        _;
    }

    modifier electionEnded() {
        require(
            electionStatus, 
            "Election not ended yet."
        );
        _;
    }

    // when doing frontend, map the options of the voting to a index, starting from 0
    modifier validVotingChoice(uint256 votingChoice) {
        require(
            votingChoice >= 0 && votingChoice <= votingOptions.length, 
            "Invalid voting option."
        );
        _;
    }

    modifier electionOwnerOnly() {
        require(electionOwner == msg.sender, "Only election owner can perform this action.");
        _;
    }

    modifier minimumVotersReached() {
        require(voterList.length >= minimumVoters, "Election has not met minimum required number of voters.");
        _;
    }

    modifier positiveTokenBalance() {
        require(nusTokenInstance.balanceOf(address(this)) > 0, "NUS Token balance must be more than 0.");
        _;
    }

    modifier balanceEqualExceedReward() {
        require(nusTokenInstance.balanceOf(address(this)) >= votingReward, "NUS Token balance must equal or exceed voting reward.");
        _;
    }

    modifier votingRewardNotIssued() {
        require(
            !rewardStatus, 
            "Voting reward has been issued."
        );
        _;
    }

    modifier votingRewardIssued() {
        require(
            rewardStatus, 
            "Voting reward has not been issued."
        );
        _;
    }
    // main functions 

    /**
    * Function to allow user to vote, voting weightage will be based on the NUST
    * As long as the election is ongoing, the user can change their vote by revoting.
    * @param votingChoice uint256, which must be in range of the votingOptions
    **/
    function vote(uint256 votingChoice) electionOngoing validVotingChoice(votingChoice) public {
        uint256 curr_voter_NUST = nusTokenInstance.balanceOf(msg.sender);
        // uint256 curr_voter_NUST = 1;
        Voter memory curr_voter = Voter(curr_voter_NUST, true, votingChoice);
        if (voters[msg.sender].voted == false) { // voter has not voted before 
            voters[msg.sender] = curr_voter;
            voterList.push(msg.sender);
            totalVotes += curr_voter_NUST; // totalVotes does not update if voter voted, then gained new tokens, and voted again
        } else { // voter has voted before, voter is changing vote 
            voters[msg.sender] = curr_voter;
        }
    }

    /**
    * Function to tally vote, once the tally of vote is completed, the election has ended. 
    * This function will update votingResults and votingResultsList
    **/
    function tallyVote() public electionOngoing electionOwnerOnly minimumVotersReached {
        // count the votes 
        for (uint256 i=0; i<voterList.length; i++) {
            Voter memory curr_voter = voters[voterList[i]];
            votingResults[curr_voter.vote] += curr_voter.weight;
        }

        // store result in a array 
        for (uint i = 0; i < votingOptions.length; i++) {
            votingResultsList[i] = votingResults[i];
        }

        // end election
        electionStatus = true;

    }

    /**
    * Function to get the voting result after the tally of the vote is completed. 
    **/

    function getVotingResult() public electionEnded electionOwnerOnly returns(uint256[] memory) {
        // find the max vote as the winner vote 
        uint256 maxVoteCount = 0;
        uint256 totalNumberWinningVote = 0; // to keep track if there is a draw 
        for (uint256 i=0; i<votingResultsList.length; i++) {
            if (votingResultsList[i] == 0) {
                // if vote count for this option is 0, just skip 
                continue;
            }
            else if (votingResultsList[i] > maxVoteCount) {
                maxVoteCount = votingResultsList[i];
                totalNumberWinningVote = 1;
            } else if (votingResultsList[i] == maxVoteCount) { // draw 
                totalNumberWinningVote += 1;
            } 
        }

        if (totalNumberWinningVote == 0) {
            // means no one voted at all 
            // maybe should put a modifier for tallyVote() to ensure there is at least a certain amount of people that voted before closing the voting
            emit noOneVoted();
        } else if (totalNumberWinningVote == 1) {
            // there is only 1 winning vote 
            for (uint256 i=0; i<votingResultsList.length; i++) {
                if (votingResultsList[i] == maxVoteCount) {
                    emit winningVote(i, votingResultsList[i]);
                    break;
                }
            }
        } else { 
            // there is multple wining option / draw 
            emit draw(maxVoteCount);
            for (uint256 i=0; i<votingResultsList.length; i++) {
                if (votingResultsList[i] == maxVoteCount) {
                    emit drawVotes(i);
                }
            }

        }

        return votingResultsList;

        // ignore this part first 
        // uint256 majority = (totalVotes - 1) / votingOptions.length + 1;
        // uint256 winningVoteCount = 0;
        // bool[] memory winningTracker = new bool[](votingOptions.length); // true for winning vote, default to false
        // // majority winner 
        // for (uint256 i=0; i<votingResultsList.length; i++) {
        //     if (votingResultsList[i] >= majority) {
        //         winningTracker[i] = true;
        //         winningVoteCount += 1;
        //     }
        // }

        // if (totalVotes < votingOptions.length) {
        //     // cannot do majority for this case 

        //     return votingResultsList;
        // }

        // if (winningVoteCount == 0) {
        //     emit noWinningVote();
        // } else if (winningVoteCount == 1) {  // 1 majority winning vote
        //     for (uint256 i=0; i<winningTracker.length; i++) {
        //         if (winningTracker[i]) {
        //             emit winningVote(i);
        //             break;
        //         }
        //     }
        // } else { // multiple winning vote / draw 
        //     emit draw();
        //     for (uint256 i=0; i<winningTracker.length; i++) {
        //         if (winningTracker[i]) {
        //             emit multpleWinningVote(i);
        //         }
        //     }
        // }
        
    }

    function issueVotingReward() public balanceEqualExceedReward electionEnded electionOwnerOnly votingRewardNotIssued {
        for (uint256 i=0; i<voterList.length; i++) {
            if(nusTokenInstance.balanceOf(address(this)) >= votingReward) {
                nusTokenInstance.takeTokensGiveTo(address(this), voterList[i], votingReward);
                votersRewarded[voterList[i]] = true;
            }
        }
        //  voting rewards completed
        rewardStatus = true;
    }
    // NUSElections contract address needs to be whitelisted by NUSToken contract to giveTokens

    function returnTokenToAdmin() public positiveTokenBalance electionEnded electionOwnerOnly votingRewardIssued {
        uint256 nusElectionsBalance = nusTokenInstance.balanceOf(address(this));
        nusTokenInstance.takeTokensGiveTo(address(this), address(nusTokenInstance), nusElectionsBalance);
    }

    // getters and helpers 
    function hasVoted(address userAddress) public view returns(bool) {
        return voters[userAddress].voted; // because getVotingChoice returns 0 by default even if voter has not voted
    }

    function getVotingChoice() public view returns(uint256) {
        return voters[msg.sender].vote;
    }

    // function getTotalVotes() public view returns(uint256) {
    //     return totalVotes;
    // }

    function getMinimumNumVoters() public view returns(uint256) {
        return minimumVoters;
    }

    function getCurrentNumVoters() public view returns(uint256) {
        return voterList.length;
    }

    function showVotingResult() public view electionEnded returns(uint256[] memory) {
        return votingResultsList;
    }

    function getElectionStatus() public view returns(bool) {
        return electionStatus;
    }

    function getRewardStatus() public view returns(bool) {
        return rewardStatus;
    }

    function showElectionBalance() public view electionOwnerOnly returns(uint256) {
        return nusTokenInstance.balanceOf(address(this));
    }

    function showVotingReward() public view returns(uint256) {
        return votingReward;
    }

    function showRewardedVoter(address voterAddress) public view electionEnded returns(bool) {
        return votersRewarded[voterAddress];
    }
}