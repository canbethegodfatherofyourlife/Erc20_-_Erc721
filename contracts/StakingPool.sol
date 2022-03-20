// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract StakingToken is ERC20, Ownable, ReentrancyGuard {

    uint256 public immutable stakingBase = 10**18;

    using SafeMath for uint256;

    // Time at which distribution ends
    uint256 public periodFinish;

    // Reward per second given to the staking contract, split among the staked tokens
    uint256 public rewardRate;

    // Duration of the reward distribution
    uint256 public rewardsDuration = 7 days;

    // Last time `rewardPerTokenStored` was updated
    uint256 public lastUpdateTime;

    // Helps to compute the amount earned by someone
    // Cumulates rewards accumulated for one token since the beginning.
    // Stored as a uint so it is actually a float times the base of the reward token
    uint256 public rewardPerTokenStored;

    // Stores for each account the rewardPerToken; we do the difference between the current and the old value to compute what has been earned by an account
    mapping(address => uint256) public userRewardPerTokenPaid;

    address[] internal stakeholders;   // list of all stakeholders
    mapping(address => uint256) internal stakes;    // The stakes for each stakeholder.
    mapping(address => uint256) internal rewards;   // The accumulated rewards for each stakeholder.

    // token price for ETH
    uint256 public tokensPerEth = 1000;

    constructor()  ERC20("Godfather", "GDF")
    { 
        _mint(msg.sender, 1000 * 10 ** decimals());
    }

    // Checks to see if the calling address is the zero address
    modifier zeroCheck(address account) {
        require(account != address(0), "0");
        _;
    }

    //  Called frequently to update the staking parameters associated to an address
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    // It adds to the reward per token: the time elapsed since the `rewardPerTokenStored` was last updated multiplied by the `rewardRate` divided by the number of tokens
    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            (((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * stakingBase) / totalSupply());
    }

    // Returns how much a given account earned rewards
    // It adds to the rewards the amount of reward earned since last time that is the difference
    // in reward per token from now and last time multiplied by the number of tokens staked by the person
    function earned(address account) public view returns (uint256) {
        return
            (balanceOf(account) * (rewardPerToken() - userRewardPerTokenPaid[account])) /
            stakingBase +
            rewards[account];
    }


    function buyToken(address receiver) public payable returns (uint256){
        uint256 tokenAmount = msg.value / (1 * 10 ** decimals()) * tokensPerEth;
        
        _mint(receiver, tokenAmount);
        
        return tokenAmount;
    }

    function modifyTokenBuyPrice(uint256 _tokenPrice) public onlyOwner returns (uint256)
    {
        tokensPerEth = _tokenPrice;
        
        emit TokenPriceUpdated(tokensPerEth);

        return tokensPerEth;
    }

    // A method for a stakeholder to create a stake.
    // The size of the stake to be created.
    function createStake(uint256 _stake)
        public
        nonReentrant
        updateReward(msg.sender)
    {
        _burn(msg.sender, _stake);
        if(stakes[msg.sender] == 0) addStakeholder(msg.sender);
        stakes[msg.sender] = stakes[msg.sender].add(_stake);
        emit Staked(msg.sender, _stake);
    }

    function removeStake(uint256 _stake)
        public
        nonReentrant 
        updateReward(msg.sender)
    {
        stakes[msg.sender] = stakes[msg.sender].sub(_stake);
        if(stakes[msg.sender] == 0) removeStakeholder(msg.sender);
        _mint(msg.sender, _stake);
        emit Withdrawn(msg.sender, _stake);
    }

    function stakeOf(address _stakeholder)
        public
        view
        returns(uint256)
    {
        return stakes[_stakeholder];
    }

    function totalStakes()
        public
        view
        returns(uint256)
    {
        uint256 _totalStakes = 0;
        for (uint256 s = 0; s < stakeholders.length; s += 1){
            _totalStakes = _totalStakes.add(stakes[stakeholders[s]]);
        }
        return _totalStakes;
    }

    function isStakeholder(address _address)
        public
        view
        returns(bool, uint256)
    {
        for (uint256 s = 0; s < stakeholders.length; s += 1){
            if (_address == stakeholders[s]) return (true, s);
        }
        return (false, 0);
    }

    function addStakeholder(address _stakeholder)
        public
    {
        (bool _isStakeholder, ) = isStakeholder(_stakeholder);
        if(!_isStakeholder) stakeholders.push(_stakeholder);
    }

    function removeStakeholder(address _stakeholder)
        public
    {
        (bool _isStakeholder, uint256 s) = isStakeholder(_stakeholder);
        if(_isStakeholder){
            stakeholders[s] = stakeholders[stakeholders.length - 1];
            stakeholders.pop();
        } 
    }

    function rewardOf(address _stakeholder) 
        public
        view
        returns(uint256)
    {
        return rewards[_stakeholder];
    }

    function totalRewards()
        public
        view
        returns(uint256)
    {
        uint256 _totalRewards = 0;
        for (uint256 s = 0; s < stakeholders.length; s += 1){
            _totalRewards = _totalRewards.add(rewards[stakeholders[s]]);
        }
        return _totalRewards;
    }

    function calculateReward(address _stakeholder)
        public
        view
        returns(uint256)
    {
        return stakes[_stakeholder] / 100;
    }

    function distributeRewards() 
        public
        onlyOwner
    {
        for (uint256 s = 0; s < stakeholders.length; s += 1){
            address stakeholder = stakeholders[s];
            uint256 reward = calculateReward(stakeholder);
            rewards[stakeholder] = rewards[stakeholder].add(reward);
        }
    }

    function withdrawReward() 
        public
    {
        uint256 reward = rewards[msg.sender];
        rewards[msg.sender] = 0;
        _mint(msg.sender, reward);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            _mint(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() public {
        removeStake(balanceOf(msg.sender));
        getReward();
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event TokenPriceUpdated(uint256 newPrice);


}