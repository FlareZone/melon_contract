// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


interface  IProposalLogic {
    // 类型声明
    // 提案
    struct Proposal {
        address proposer; // 提案发起人
        string description; // 提案描述
        uint256 stakeAmount; // 质押代币数量
        bool active; // 提案是否活跃
        bool isSettled; // 添加属性以跟踪提案是否已结算
        bool isWagered;
        uint256 endTime;
    }
    // 提议选项
    struct Option {
        string description; // 选项描述
        uint256 voteCount; // 投票计数
    }
    // 质押
    struct Stake {
        uint256 amount; // 质押的金额
        uint256 unlockTime; // 资金解锁的时间
        address staker; // 质押者地址
        bool isWagered; //是否对赌
    }
    // 投票记录
    struct VoteRecord {
        uint256 proposalId; // 提案ID
        uint256 optionId; // 用户选择的选项ID
        uint256 amount; // 投票数量
    }
    //事件
    event Received(address caller, uint amount, string message);
    event Deposited(address indexed user, uint amount);
    event Withdrawn(address indexed user, uint amount);
    event Voted(
        address indexed _address,
        uint256 indexed _proposalId,
        uint256 indexed _optionId,
        uint256 _amount
    );
    event ProposalAndOptionsSubmitted(
        address indexed user,
        uint256 indexed proposalIndex,
        string proposalDescription,
        string[] optionDescriptions,
        uint256 endtime
    );
    event DepositForProposal(
        address indexed staker,
        uint256 amount,
        bool staked,
        uint256 unlockTime,
        uint256 indexed stakeIndex
    );
    event TokensStaked(
        address indexed user,
        uint256 amount,
        bool isForProposal
    );
    event FundsSettledForAverageQuality(
        uint256 indexed proposalId,
        address indexed proposer,
        uint256 amountToReturn
    );
    event WithdrawalDetailed(
        address indexed user,
        uint256 amountWithdrawn,
        uint256 balanceAfterWithdrawal
    );
    event UnlockTimeUpdated(
        address indexed staker,
        uint256 indexed stakeIndex,
        uint256 newUnlockTime
    );
    event FundsPenalizedForNonCompliance(
        uint256 indexed proposalId,
        address indexed proposer,
        uint256 penalty
    );
    event ProposalStatusChanged(uint256 proposalId, bool isActive);
    event ProposalEndTime(uint256 _proposalId, uint256 endTime);
    event ProposalForUser(
        address indexed userAddress,
        uint256 indexed proposalId,
        string proposalDescription,
        uint256 stakeAmount,
        string[] optionDescriptions,
        uint256 endtime
    );
    event StakeReleased(
        address indexed user,
        uint256 stakeIndex,
        bool penalized,
        uint256 amountReleased
    );
    event ProposalEnded(uint256 indexed proposalId, bool isActive);
    event ProposalConcluded(uint256 indexed proposalId, bool isActive);
    event RewardDistributed(
        address indexed voter,
        uint256 proposalId,
        uint256 amount,
        bool isWinner
    );
    event ExchangePoints(address indexed user, uint256 points);
    // 错误

    // 积分兑换
    function exchangePoints(uint256 amount) external;

    function getUserBalance(address) external view returns (uint256);

    function getUserVotingRights(address userAddress) external view returns (uint256);
    
    function deposit(uint256 amount) external;

    // Submit a proposal for review
    function submitProposalForReview(uint256 amount) external returns (uint256);

    // Create a proposal with multiple options
    function createProposalWithOptions(
        string memory proposalDescription,
        string[] memory optionDescriptions,
        uint amount,
        uint256 endtime
    ) external returns (uint256);

    // Process a user's stake in a proposal
    function processUserStakedProposal(
        address userAddress,
        string memory proposalDescription,
        uint256 stakeAmount,
        string[] memory optionDescriptions,
        uint256 stakeIndex,
        uint256 endtime
    ) external returns (uint256);

    // Withdraw from the contract
    function withdraw(uint256 _amount) external;

    // Get the available balance that can be withdrawn
    function getAvailableWithdrawBalance(
        address user
    ) external view returns (uint256);

    // Check the status of a proposal
    function getProposalStatus(
        uint256 _proposalId
    ) external view returns (bool);

    // Vote on a proposal's option
    function vote(
        uint256 _proposalId,
        uint256 _optionId,
        uint256 _amount
    ) external;

    // Get the contract's balance
    function getContractBalance() external view returns (uint);

    // Pause the contract
    function pause() external;

    // Unpause the contract
    function unpause() external;

    // Get a user's voting history
    function getUserVotingHistory(
        address _user
    )
        external
        view
        returns (uint256[] memory, uint256[] memory, uint256[] memory);

    // Get the length of the proposals array
    function proposalsLength() external view returns (uint256);

    // Get the number of options for a proposal
    function getOptionsCount(
        uint256 proposalId
    ) external view returns (uint256);

    // Get the vote count for an option in a proposal
    function getOptionVoteCount(
        uint256 proposalId,
        uint256 optionIndex
    ) external view returns (uint256);

    // Get the ID of the current proposal
    function getCurrentProposalId() external view returns (uint256);

    // Process a stake release
    function handleStakeRelease(
        address user,
        uint256 stakeIndex,
        bool penalizeStake
    ) external;

    // Settle rewards
    function settleRewards(
        uint256 proposalId,
        uint256 winningOptionId
    ) external;

    // Settle funds for the average quality
    function settleFundsForAverageQuality(uint256 _proposalId) external;

    // Verify compliance and expectations
    function verifyComplianceAndExpectations(
        uint256 _proposalId
    ) external;

    // Check if the quality compliance is below expectations
    function checkQualityComplianceBelowExpectations(
        uint256 _proposalId
    ) external;

    // Deactivate a proposal
    function deactivateProposal(uint256 _proposalId) external;
}
