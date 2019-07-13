pragma solidity ^0.5.7;

interface CTokenInterface {
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function liquidateBorrow(address borrower, uint repayAmount, address cTokenCollateral) external returns (uint);
    function liquidateBorrow(address borrower, address cTokenCollateral) external payable;
    function exchangeRateCurrent() external returns (uint);
    function getCash() external view returns (uint);
    function totalBorrowsCurrent() external returns (uint);
    function borrowRatePerBlock() external view returns (uint);
    function supplyRatePerBlock() external view returns (uint);
    function totalReserves() external view returns (uint);
    function reserveFactorMantissa() external view returns (uint);
    function borrowBalanceCurrent(address account) external returns (uint);

    function totalSupply() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256 balance);
    function allowance(address, address) external view returns (uint);
    function approve(address, uint) external;
    function transfer(address, uint) external returns (bool);
    function transferFrom(address, address, uint) external returns (bool);
}

interface CERC20Interface {
    function mint(uint mintAmount) external returns (uint); // For ERC20
    function repayBorrow(uint repayAmount) external returns (uint); // For ERC20
    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint); // For ERC20
    function borrowBalanceCurrent(address account) external returns (uint);
}

interface CETHInterface {
    function mint() external payable; // For ETH
    function repayBorrow() external payable; // For ETH
    function repayBorrowBehalf(address borrower) external payable; // For ETH
    function borrowBalanceCurrent(address account) external returns (uint);
}

interface ERC20Interface {
    function allowance(address, address) external view returns (uint);
    function balanceOf(address) external view returns (uint);
    function approve(address, uint) external;
    function transfer(address, uint) external returns (bool);
    function transferFrom(address, address, uint) external returns (bool);
}

interface ComptrollerInterface {
    function enterMarkets(address[] calldata cTokens) external returns (uint[] memory);
    function exitMarket(address cTokenAddress) external returns (uint);
    function getAssetsIn(address account) external view returns (address[] memory);
    function getAccountLiquidity(address account) external view returns (uint, uint, uint);
}

interface CompOracleInterface {
    function getUnderlyingPrice(address) external view returns (uint);
}

interface SplitSwapInterface {
    function getBest(address src, address dest, uint srcAmt) external view returns (uint bestExchange, uint destAmt);
    function ethToDaiSwap(uint splitAmt, uint slippageAmt) external payable returns (uint destAmt);
    function daiToEthSwap(uint srcAmt, uint splitAmt, uint slippageAmt) external returns (uint destAmt);
}


contract DSMath {

    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "math-not-safe");
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        z = x - y <= x ? x - y : 0;
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "math-not-safe");
    }

    uint constant WAD = 10 ** 18;

    function wmul(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, y), WAD / 2) / WAD;
    }

    function wdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, WAD), y / 2) / y;
    }

}


contract Helpers is DSMath {

    /**
     * @dev get ethereum address for trade
     */
    function getAddressETH() public pure returns (address eth) {
        eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    }

    /**
     * @dev get ethereum address for trade
     */
    function getAddressDAI() public pure returns (address dai) {
        dai = 0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359;
    }

    /**
     * @dev get Compound Comptroller Address
     */
    function getComptrollerAddress() public pure returns (address troller) {
        troller = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    }

    /**
     * @dev get Compound Comptroller Address
     */
    function getCompOracleAddress() public pure returns (address troller) {
        troller = 0xe7664229833AE4Abf4E269b8F23a86B657E2338D;
    }

    /**
     * @dev get Compound Comptroller Address
     */
    function getCETHAddress() public pure returns (address cEth) {
        cEth = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    }

    /**
     * @dev get Compound Comptroller Address
     */
    function getCDAIAddress() public pure returns (address cDai) {
        cDai = 0xF5DCe57282A584D2746FaF1593d3121Fcac444dC;
    }

    /**
     * @dev get admin address
     */
    function getAddressSplitSwap() public pure returns (address payable splitSwap) {
        splitSwap = 0xa4BCA645f9cB9e6F9ad8C56D90a65b07C2f4e1Dd;
    }

    function enterMarket(address cErc20) internal {
        ComptrollerInterface troller = ComptrollerInterface(getComptrollerAddress());
        address[] memory markets = troller.getAssetsIn(address(this));
        bool isEntered = false;
        for (uint i = 0; i < markets.length; i++) {
            if (markets[i] == cErc20) {
                isEntered = true;
            }
        }
        if (!isEntered) {
            address[] memory toEnter = new address[](1);
            toEnter[0] = cErc20;
            troller.enterMarkets(toEnter);
        }
    }

    /**
     * @dev setting allowance to compound for the "user proxy" if required
     */
    function setApproval(address erc20, uint srcAmt, address to) internal {
        ERC20Interface erc20Contract = ERC20Interface(erc20);
        uint tokenAllowance = erc20Contract.allowance(address(this), to);
        if (srcAmt > tokenAllowance) {
            erc20Contract.approve(to, 2**255);
        }
    }

}


contract CompoundHelper is Helpers {

    /**
     * @dev get user's token supply and borrow in ETH
     */
    function compSupplyBorrow(address cTokenAdd, address user) public returns(uint supplyInEth, uint borrowInEth) {
        CTokenInterface cTokenContract = CTokenInterface(cTokenAdd);
        uint tokenPriceInEth = CompOracleInterface(getCompOracleAddress()).getUnderlyingPrice(cTokenAdd);
        uint cTokenBal = sub(cTokenContract.balanceOf(user), 1);
        uint cTokenExchangeRate = cTokenContract.exchangeRateCurrent();
        uint tokenSupply = sub(wmul(cTokenBal, cTokenExchangeRate), 1);
        supplyInEth = sub(wmul(tokenSupply, tokenPriceInEth), 10);
        uint tokenBorrowed = cTokenContract.borrowBalanceCurrent(user);
        borrowInEth = add(wmul(tokenBorrowed, tokenPriceInEth), 10);
    }

    /**
     * @dev get users overall details for Compound
     */
    function getCompStats(
        address user,
        address[] memory cTokenAddr,
        uint[] memory cTokenFactor
    ) public returns (uint totalSupply, uint totalBorrow, uint maxBorrow, uint borrowRemain, uint maxWithdraw, uint ratio)
    {
        for (uint i = 0; i < cTokenAddr.length; i++) {
            address cTokenAdd = cTokenAddr[i];
            uint factor = cTokenFactor[i];
            (uint supplyInEth, uint borrowInEth) = compSupplyBorrow(cTokenAdd, user);
            totalSupply += supplyInEth;
            totalBorrow += borrowInEth;
            maxBorrow += wmul(supplyInEth, factor);
        }
        borrowRemain = sub(maxBorrow, totalBorrow);
        maxWithdraw = wdiv(borrowRemain, 750000000000000000); // divide it by 0.75 (ETH Factor)
        uint userEthSupply = getEthSupply(user);
        maxWithdraw = userEthSupply > maxWithdraw ? maxWithdraw : userEthSupply;
        ratio = wdiv(totalBorrow, totalSupply);
    }

    function getEthSupply(address user) internal returns (uint ethSupply) {
        CTokenInterface cTokenContract = CTokenInterface(getCETHAddress());
        uint cTokenBal = sub(cTokenContract.balanceOf(user), 1);
        uint cTokenExchangeRate = cTokenContract.exchangeRateCurrent();
        ethSupply = wmul(cTokenBal, cTokenExchangeRate);
    }

    function getDaiRemainBorrow(uint daiInEth) internal view returns (uint daiAmt) {
        uint tokenPriceInEth = CompOracleInterface(getCompOracleAddress()).getUnderlyingPrice(getCDAIAddress());
        daiAmt = sub(wdiv(daiInEth, tokenPriceInEth), 10);
    }

}


contract CompoundResolver is CompoundHelper {

    event LogMint(address erc20, address cErc20, uint tokenAmt, address owner);
    event LogRedeem(address erc20, address cErc20, uint tokenAmt, address owner);
    event LogBorrow(address erc20, address cErc20, uint tokenAmt, address owner);
    event LogRepay(address erc20, address cErc20, uint tokenAmt, address owner);

    /**
     * @dev Deposit ETH/ERC20 and mint Compound Tokens
     */
    function mintCEth(uint tokenAmt) internal {
        enterMarket(getAddressETH());
        CETHInterface cToken = CETHInterface(getAddressETH());
        cToken.mint.value(tokenAmt)();
        emit LogMint(
            getAddressETH(),
            getAddressETH(),
            tokenAmt,
            msg.sender
        );
    }

    /**
     * @dev Redeem ETH/ERC20 and mint Compound Tokens
     * @param tokenAmt Amount of token To Redeem
     */
    function redeemEth(uint tokenAmt) internal {
        CTokenInterface cToken = CTokenInterface(getCETHAddress());
        setApproval(getCETHAddress(), 10**30, getCETHAddress());
        require(cToken.redeemUnderlying(tokenAmt) == 0, "something went wrong");
        emit LogRedeem(
            getAddressETH(),
            getCETHAddress(),
            tokenAmt,
            address(this)
        );
    }

    /**
     * @dev borrow ETH/ERC20
     */
    function borrow(uint tokenAmt) internal {
        enterMarket(getCDAIAddress());
        require(CTokenInterface(getCDAIAddress()).borrow(tokenAmt) == 0, "got collateral?");
        emit LogBorrow(
            getAddressDAI(),
            getCDAIAddress(),
            tokenAmt,
            address(this)
        );
    }

    /**
     * @dev Pay Debt ETH/ERC20
     */
    function repayDai(uint tokenAmt) internal {
        CERC20Interface cToken = CERC20Interface(getCDAIAddress());
        setApproval(getAddressDAI(), tokenAmt, getCDAIAddress());
        require(cToken.repayBorrow(tokenAmt) == 0, "transfer approved?");
        emit LogRepay(
            getAddressDAI(),
            getCDAIAddress(),
            tokenAmt,
            address(this)
        );
    }

}


contract CompoundSave is CompoundResolver {

    event LogSaveCompound(uint srcETH, uint destDAI);

    event LogLeverageCompound(uint srcDAI,uint destETH);

    function save(
        uint ethToFree,
        address[] memory cTokenAddr,
        uint[] memory ctokenFactor,
        uint splitAmt,
        uint slippageAmt
    ) public
    {
        (,,,,uint maxWithdraw,) = getCompStats(address(this), cTokenAddr, ctokenFactor);
        uint ethToSwap = ethToFree < maxWithdraw ? ethToFree : maxWithdraw;
        redeemEth(ethToSwap);
        uint destAmt = SplitSwapInterface(getAddressSplitSwap()).ethToDaiSwap.value(ethToSwap)(splitAmt, slippageAmt);
        repayDai(destAmt);
        emit LogSaveCompound(ethToSwap, destAmt);
    }

    function leverage(
        uint daiToBorrow,
        address[] memory cTokenAddr,
        uint[] memory ctokenFactor,
        uint splitAmt,
        uint slippageAmt
    ) public
    {
        (,,,uint borrowRemain,,) = getCompStats(address(this), cTokenAddr, ctokenFactor);
        uint daiToSwap = getDaiRemainBorrow(borrowRemain);
        daiToSwap = daiToSwap < daiToBorrow ? daiToSwap : daiToBorrow;
        borrow(daiToSwap);
        uint destAmt = SplitSwapInterface(getAddressSplitSwap()).daiToEthSwap(daiToSwap, splitAmt, slippageAmt);
        mintCEth(destAmt);
    }

}


contract InstaCompSave is CompoundResolver {

    uint public version;

    /**
     * @dev setting up variables on deployment
     * 1...2...3 versioning in each subsequent deployments
     */
    constructor(uint _version) public {
        version = _version;
    }

    function() external payable {}

}