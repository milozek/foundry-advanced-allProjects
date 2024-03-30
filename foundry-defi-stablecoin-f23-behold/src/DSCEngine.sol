// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title DSCEngine
 * @author Patrick Collins
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg.
 * The stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had: no governance, no fees, and was only backed by wETH and wBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of all collateral be <= the (US$ backed value) of all the DSC. -> we should always collateral > stablecoin -> burnDSC()
 *
 * @notice This contract is the core of the DSC system. It handles all the logic for minting and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 *
 */

// Threshold to let's say 150% --->>> then, in this case, if i have $50 DSC, i need to have $75 ETH at all times > Buffer to never be undercollateralized

// $100 ETH ---> if its value drops ---> $40 ETH . bad ---> then: $75 ETH at least. if it drops to $74, then --> LIQUIDATE
// $50 DSC

// Hey, if someone pays back your minted DSC, they can have all your collateral for a discount.

/**
 * Clarification Example:
 *
 * - $100 ETH Collateral
 * - $50 DSC minted
 * - My collateral drops to $74 ETH
 * - UNDERCOLLATERALIZED!!!
 * - My DSC -> $0
 * - This is my punishment for letting my collateral get too low.
 *
 * - OTHER PERSON: I pay back your $50 DSC and ---> Get ALL my collateral!
 * - $74 ETH
 * - -$50 DSC
 * - $24 just by liquidating me, they're incentivized to make money
 *
 *
 *
 */
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract DSCEngine is ReentrancyGuard {
    /**
     * is DecentralizedStableCoin
     */
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; //10%

    // mapping (address => bool) private s_tokenToAllowed;
    // because we know we gonna use PriceFeeds from CL, we gonna do: ->
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    // event CollateralRedeemed(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        // i.e: eth/usd, btc/usd, etc
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }
    /**
     *
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDscToMint The amount of dsc to mint
     * @notice This fn will deposit your collateral and mint DSC in one tx.
     */

    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDscToMint);
    }

    /**
     * @notice follows CEI checks effects interactions
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     *
     * @param tokenCollateralAddress The collateral address to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn The amount of DSC to burn
     * @notice this fn burns dsc and redeems underlying collateral in 1 tx
     */
    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDSC(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral() already checks healthFactor.
    }

    // in order to redeem collateral:
    // 1.   health factor must be over 1 AFTER collateral pulled
    // DRY: Don't repeat yourself (code in different ways to avoid getting to the point where: Oh, maybe what i've been doing is wrong)

    //CEI -> sometimes get violated when i need to check something AFTER a token transfer has happened.
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        // we need an internal fn to redeem anybody;
        // this
        //100 -1000(revert) -> newer versions of solidity based on SafeMath.
        /**
         * s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
         *     emit CollateralRedeemed(msg.sender, tokenCollateralAddress, amountCollateral);
         *     bool success = IERC20(tokenCollateralAddress).transfer(msg.sender, amountCollateral);
         *     if (!success) {
         *         revert DSCEngine__TransferFailed();
         *     }
         */
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // $100 ETH -> $20 DSC
    // 100 (break)
    // 1. burn dsc
    // 2. redeem eth

    // someone can be willing to deposit $200 ETH but minting only $20 DSC
    /**
     *
     * @param amountDscToMint The amount of dsc to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintDSC(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        // If they minted too much ($150 DSC, $100 ETH)
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDSC(uint256 amount) public moreThanZero(amount) {
        // s_DSCMinted[msg.sender] -= amount;
        // bool success = i_dsc.transferFrom(msg.sender, address(this), amount);
        // // this conditional is hypothetically unreachable
        // if (!success) {
        //     revert DSCEngine__TransferFailed();
        // }
        // i_dsc.burn(amount);
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // i don't think this would ever be needed.
    }

    // if we do start nearing undercollateralization, we need someone to liquidate positions

    // $100 eth $50 dsc
    // $20 eth $50 dsc <- DSC isn't worth $1!!!

    // $75 backing $50 DSC
    // Liquidator take $75 backing and burns off the $50 DSC

    //if someone is almost undercollateralized we'll pay you to liquidate them! (like a game)

    /**
     *
     * @param collateral The ERC20 collateral address to liquidate from the user
     * @param user The user who has broken the healthFactor. their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DSC you want to burn to improve the users healthFactor
     * @notice you can partially liquidate a user.
     * @notice you'll get a liquidation bonus for taking the users funds.
     * @notice this fn working assumes the protocol will be roughly 200% overcollateralized in order for this to work.
     * @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentivate the liquidators.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     *
     * CEI
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        // key thing that holds the whole sc together
        // remove ppls positions to save the protocol. VERY important

        // need to check healthfactor, is the user liquidatable?
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // we want to burn the dsc debt and take their collateral / remove them from the system
        // Bad User: $140 eth $100 dsc
        // debt to cover $100
        // $100 DSC = ??? ETH?
        // 0.05 eth
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // give them a 10% bonus, incentivize the liquidator ==> $110 weth for $100 dsc
        // we SHOULD (but won't) implement a feature to liquidate in the event the protocol is insolvent
        // and sweep extra amounts into a treasury

        // 0.05 * 0.01 = 0.005. gettin 0.055
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        // we need to burn the dsc
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {}

    /**
     * @dev Low-level internal fn. do not call unless the fn calling it
     * is checking for health factor being broken
     */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        // this conditional is hypothetically unreachable
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    // moreThanZero(amountCollateral)
    // nonReentrant
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        // _revertIfHealthFactorIsBroken(msg.sender);
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValueInUsd(user);
    }

    /**
     * Returns how close to liquidation user is
     * If a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        // BUG IN HERE

        // total DSC minted
        // total collateral VALUE
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
        /**
         *
         * 1000 ETH * 50 = 50,000 / 100 = 500
         *
         * $150 ETH / 100 DSC = 1.5
         * 150 * 50 = 7500 / 100 = (75 / 100) < 1
         *  return (collateralValueInUsd / totalDscMinted);
         *
         */

        // 100 / 100 we never want to be UNDERcollateralized, && ALWAYS want to be OVERcollateralized.
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1. check health factor, enough collateral?
        // 2. revert if not enough
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token, get the amount they have deposited,
        // and map it to the price, to get the value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // 1 ETH = $1000
        // The returned value from CL will be 1000 * 1e8
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION; //1e18; // (1000 * 1e8 *(1e10)) *1000 * 1e18;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        //price of eth(token)
        // $/eth eth??
        // price:$2000 / ETH. actualAmount$1000 = 0.5 eth
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }
}
