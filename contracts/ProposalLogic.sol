// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "./IProposalLogic.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Counters.sol";

contract ProposalLogic is IProposalLogic, ReentrancyGuard, Pausable, Ownable {
    // state variable
    address public flareToken; // Token Address
    using Counters for Counters.Counter;
    Proposal[] public proposals; // Proposal array

    mapping(address => uint256) public balances;
    mapping(uint256 => Option[]) public proposalOptions; // Proposal options
    mapping(address => uint256) public proposalDeposit; // The amount at which the user initiates a proposal
    mapping(address => uint256) public votingDeposit; // The amount voted by the user
    mapping(uint => mapping(uint => Vote[])) public votingRecordsforProposals;
    mapping(uint256 => uint) public winningOptionByProposal; // Record the winning options for settled proposals
    mapping(uint => mapping(address => int))
        public rewardOrPenaltyInSettledProposal; // Record rewards or punishments for settlement proposal users

    // Modifier

    // function
    constructor(address myToken) Ownable(msg.sender) {
        flareToken = myToken;
    }

    function getOptionsCount(uint256 proposalId) public view returns (uint256) {
        return proposalOptions[proposalId].length;
    }

    function deposit(uint256 amount) public {
        require(
            IERC20(flareToken).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        balances[msg.sender] = balances[msg.sender] + amount;
        emit Deposited(msg.sender, amount);
    }

    function createProposal(
        address user,
        string memory description,
        uint256 amount,
        string[] memory options,
        uint256 endtime
    ) public onlyOwner {
        uint availableBalance = balances[user] - votingDeposit[user];
        if (availableBalance < amount) {
            revert InsufficientBalance(user, availableBalance);
        } else {
            proposalDeposit[user] += amount;
        }

        uint256 unlockTime = block.timestamp + (endtime * 1 days);
        uint256 newId = proposals.length;
        proposals.push(
            Proposal({
                proposer: user,
                description: description,
                stakeAmount: amount,
                active: true,
                isSettled: false,
                isWagered: amount > 0,
                endTime: unlockTime
            })
        );
        for (uint256 i = 0; i < options.length; i++) {
            proposalOptions[newId].push(
                Option({description: options[i], voteCount: 0})
            );
        }
        emit CreateProposal(
            user,
            newId,
            description,
            amount,
            options,
            unlockTime
        );
    }

    function exchangePoints(uint256 points) public {
        require(points > 0, "Points must be greater than zero");
        balances[msg.sender] += points;
        emit ExchangePoints(msg.sender, points);
    }

    function withdraw(uint256 amount) public nonReentrant {
        // Ensure that users have sufficient balance to withdraw
        uint256 availableBalance = getAvailableBalance(msg.sender);
        require(
            availableBalance >= amount,
            "Not enough available balance to withdraw"
        );
        require(
            IERC20(flareToken).transfer(msg.sender, amount),
            "Transfer failed"
        );
        balances[msg.sender] = balances[msg.sender] - amount;
        emit WithdrawalDetailed(msg.sender, amount, balances[msg.sender]);
    }

    function getAvailableBalance(address user) public view returns (uint256) {
        uint256 totalBalance = balances[user];
        uint256 lockedForVoting = votingDeposit[user];
        uint256 lockedInProposals = proposalDeposit[user];
        uint256 totalLocked = lockedForVoting + lockedInProposals;
        return totalBalance > totalLocked ? totalBalance - totalLocked : 0;
    }

    function getProposalStatus(uint256 proposalId) public view returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        return proposal.active;
    }

    function vote(
        uint256 proposalId,
        uint256 optionId,
        uint256 amount
    ) public whenNotPaused {
        require(proposalId < proposals.length, "The proposal does not exist");
        require(
            optionId < proposalOptions[proposalId].length,
            "The option does not exist"
        );
        require(
            block.timestamp < proposals[proposalId].endTime,
            "The voting period for this proposal has ended"
        );
        require(proposals[proposalId].active, "The proposal is not active");
        require(
            getAvailableBalance(msg.sender) >= amount,
            "Insufficient voting rights"
        );
        votingDeposit[msg.sender] += amount;
        proposalOptions[proposalId][optionId].voteCount += amount;
        votingRecordsforProposals[proposalId][optionId].push(
            Vote(msg.sender, amount)
        );
        emit Voted(msg.sender, proposalId, optionId, amount);
    }

    function isSingleOptionProposal(
        uint256 proposalId,
        uint winningOptionId
    ) public view returns (bool) {
        uint optionCount = proposalOptions[proposalId].length;
        for (uint i = 0; i < optionCount; i++) {
            if (
                i != winningOptionId &&
                proposalOptions[proposalId][i].voteCount > 0
            ) {
                return false;
            }
        }
        return true;
    }

    function settleRewards(
        uint256 proposalId,
        uint256 winningOptionId
    ) public onlyOwner nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        require(
            !proposal.active,
            "Proposal must be inactive to settle rewards."
        );
        require(!proposal.isSettled, "Rewards already settled");

        bool isSingleOptionStatus = isSingleOptionProposal(
            proposalId,
            winningOptionId
        );

        mapping(uint => Vote[]) storage voteRecords = votingRecordsforProposals[
            proposalId
        ];

        if (isSingleOptionStatus) {
            // Return all pledges in the original way
            for (uint256 i = 0; i < voteRecords[winningOptionId].length; i++) {
                Vote memory vote = voteRecords[winningOptionId][i];
                votingDeposit[vote.user] -= vote.amount;
            }
            emit ProposalRefunded(proposalId, winningOptionId);
        } else {
            uint totalStake;
            uint optionCount = proposalOptions[proposalId].length;
            // Calculate the total amount of pledged options for this proposal
            for (uint i = 0; i < optionCount; i++) {
                totalStake += proposalOptions[proposalId][i].voteCount;
            }
            // The initiator of the proposal receives a 5% reward from the pledge of the proposal
            balances[proposal.proposer] += (totalStake * 5) / 100;

            // Calculate the number of proposal tokens after extracting 5% platform fee and 5% proposal initiator reward
            uint totalStakeExtractFee = (totalStake * 90) / 100;

            for (
                uint optionIndex = 0;
                optionIndex < optionCount;
                optionIndex++
            ) {
                Vote[] memory votes = voteRecords[optionIndex];
                for (
                    uint voteIndex = 0;
                    voteIndex < votes.length;
                    voteIndex++
                ) {
                    Vote memory voteInfo = votes[voteIndex];
                    votingDeposit[voteInfo.user] -= voteInfo.amount;

                    if (optionIndex == winningOptionId) {
                        // Distribute rewards according to the proportion of voters pledging
                        uint voterReward = (voteInfo.amount *
                            totalStakeExtractFee) /
                            proposalOptions[proposalId][optionIndex].voteCount;

                        voterReward -= voteInfo.amount;
                        balances[voteInfo.user] += voterReward;

                        rewardOrPenaltyInSettledProposal[proposalId][
                            voteInfo.user
                        ] = int256(voterReward);
                        emit RewardDistributed(
                            voteInfo.user,
                            proposalId,
                            voterReward,
                            true
                        );
                    } else {
                        // Calculate penalty amount
                        balances[voteInfo.user] -= voteInfo.amount;
                        rewardOrPenaltyInSettledProposal[proposalId][
                            voteInfo.user
                        ] = int256(voteInfo.amount) * -1;
                        emit RewardDistributed(
                            voteInfo.user,
                            proposalId,
                            voteInfo.amount,
                            false
                        );
                    }
                }
            }
        }
        winningOptionByProposal[proposalId] = winningOptionId;
        proposal.isSettled = true;
    }

    // 评价一般提案
    function settleFundsForAverageQuality(uint256 proposalId) public onlyOwner {
        require(proposalId < proposals.length, "Proposal does not exist.");
        Proposal storage proposal = proposals[proposalId];
        require(proposal.active, "Proposal is still active.");
        require(!proposal.isSettled, "Funds already settled");
        deactivateProposal(proposalId); // 将提案状态设置为非活跃

        uint256 stakedAmount = proposal.stakeAmount;
        if (proposal.isWagered) {
            uint256 currentDeposit = proposalDeposit[proposal.proposer];
            proposalDeposit[proposal.proposer] = stakedAmount > currentDeposit
                ? 0
                : currentDeposit - stakedAmount;
        } else {
            proposal.isSettled = true;
        }
        uint256 serviceFee = (proposal.stakeAmount * 3) / 100; // Calculating 3% service fee
        uint256 reward = (proposal.stakeAmount * 5) / 100; // Calculating 5% reward
        uint256 profit = reward - serviceFee;

        balances[proposal.proposer] += profit; // Updating balance without actual transfer

        emit FundsSettledForAverageQuality(
            proposalId,
            proposal.proposer,
            profit
        );
    }

    function verifyComplianceAndExpectations(
        uint256 proposalId
    ) public onlyOwner {
        require(proposalId < proposals.length, "Proposal does not exist.");
        Proposal storage proposal = proposals[proposalId];
        require(proposal.active, "Proposal is still active.");
        require(!proposal.isSettled, "Funds already settled");
        deactivateProposal(proposalId); // 将提案状态设置为非活跃
        uint256 stakedAmount = proposal.stakeAmount;
        if (proposal.isWagered) {
            // 确保不会导致下溢
            uint256 currentDeposit = proposalDeposit[proposal.proposer];
            proposalDeposit[proposal.proposer] = stakedAmount > currentDeposit
                ? 0
                : currentDeposit - stakedAmount;
        } else {
            proposal.isSettled = true;
        }
        uint256 serviceFee = (proposal.stakeAmount * 3) / 100; // Calculating 3% service fee
        uint256 reward = (proposal.stakeAmount * 10) / 100; // Calculating 10% reward
        uint256 profit = reward - serviceFee;

        balances[proposal.proposer] += profit; // Updating balance without actual transfer

        emit FundsSettledForAverageQuality(
            proposalId,
            proposal.proposer,
            profit
        );
    }

    function checkQualityComplianceBelowExpectations(
        uint256 proposalId
    ) public onlyOwner {
        require(proposalId < proposals.length, "Proposal does not exist.");
        Proposal storage proposal = proposals[proposalId];
        require(proposal.active, "Proposal is still active.");
        require(!proposal.isSettled, "Funds already settled");
        deactivateProposal(proposalId); // 将提案状态设置为非活跃

        uint256 stakedAmount = proposal.stakeAmount;
        if (proposal.isWagered) {
            // 确保不会导致下溢
            uint256 currentDeposit = proposalDeposit[proposal.proposer];
            proposalDeposit[proposal.proposer] = stakedAmount > currentDeposit
                ? 0
                : currentDeposit - stakedAmount;
        } else {
            proposal.isSettled = true;
        }
        uint256 punishment = (proposal.stakeAmount * 5) / 100; // Calculating 5% punishment

        balances[proposal.proposer] -= punishment; // Updating balance without actual transfer

        emit FundsPenalizedForNonCompliance(
            proposalId,
            proposal.proposer,
            punishment
        );
    }

    function deactivateProposal(uint256 proposalId) public {
        Proposal storage proposal = proposals[proposalId];
        if (block.timestamp > proposal.endTime || proposal.active) {
            proposal.active = false;
            emit ProposalStatusChanged(proposalId, false);
        }
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
