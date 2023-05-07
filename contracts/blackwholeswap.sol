// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/ERC20.sol";
import "./utils/SafeMath.sol";

contract blackholeswap is ERC20 {
    using SafeMath for *;

    /***********************************|
    |        Variables && Events        |
    |__________________________________*/

    Comptroller constant comptroller =
        Comptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
    UniswapV2Router02 constant uniswap =
        UniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    ERC20 constant Comp = ERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    ERC20 constant Dai = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    CERC20 constant cDai = CERC20(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
    CERC20 constant cUSDC = CERC20(0x39AA39c021dfbaE8faC545936693aC917d5E7563);

    event Purchases(
        address indexed buyer,
        address indexed sell_token,
        uint256 inputs,
        address indexed buy_token,
        uint256 outputs
    );
    event AddLiquidity(
        address indexed provider,
        uint256 share,
        int256 DAIAmount,
        int256 USDCAmount
    );
    event RemoveLiquidity(
        address indexed provider,
        uint256 share,
        int256 DAIAmount,
        int256 USDCAmount
    );

    /***********************************|
    |            Constsructor           |
    |__________________________________*/

    constructor() public {
        symbol = "BHSc$";
        name = "BlackHoleSwap-Compound DAI/USDC v1";
        decimals = 18;

        Dai.approve(address(cDai), uint256(-1));
        USDC.approve(address(cUSDC), uint256(-1));
        Comp.approve(address(uniswap), uint256(-1));

        address[] memory cTokens = new address[](2);
        cTokens[0] = address(cDai);
        cTokens[1] = address(cUSDC);
        uint256[] memory errors = comptroller.enterMarkets(cTokens);
        require(
            errors[0] == 0 && errors[1] == 0,
            "Comptroller.enterMarkets failed."
        );

        admin = msg.sender;
    }

    /***********************************|
    |        Governmence & Params       |
    |__________________________________*/

    uint256 public fee = 0.99985e18;
    uint256 public protocolFee = 0;
    uint256 public constant amplifier = 0.75e18;

    address private admin;
    address private vault;

    function setAdmin(address _admin) external {
        require(msg.sender == admin);
        admin = _admin;
    }

    function setParams(uint256 _fee, uint256 _protocolFee) external {
        require(msg.sender == admin);
        require(_fee < 1e18 && _fee >= 0.99e18); //0 < fee <= 1%
        if (_protocolFee > 0)
            require(uint256(1e18).sub(_fee).div(_protocolFee) >= 3); //protocolFee < 33.3% fee
        fee = _fee;
        protocolFee = _protocolFee;
    }

    function setVault(address _vault) external {
        require(msg.sender == admin);
        vault = _vault;
    }

    /***********************************|
    |         Getter Functions          |
    |__________________________________*/

    function getDaiBalance() public returns (uint256, uint256) {
        if (cDai.balanceOf(address(this)) <= 10)
            return (0, cDai.borrowBalanceCurrent(address(this)));
        else
            return (
                cDai.balanceOfUnderlying(address(this)),
                cDai.borrowBalanceCurrent(address(this))
            );
    }

    function getUSDCBalance() public returns (uint256, uint256) {
        if (cUSDC.balanceOf(address(this)) <= 10)
            return (0, cUSDC.borrowBalanceCurrent(address(this)).mul(rate()));
        else
            return (
                cUSDC.balanceOfUnderlying(address(this)).mul(rate()),
                cUSDC.borrowBalanceCurrent(address(this)).mul(rate())
            );
    }

    // DAI + USDC
    function S() external returns (uint256) {
        (uint256 a, uint256 b) = getDaiBalance();
        (uint256 c, uint256 d) = getUSDCBalance();
        return (a.add(c).sub(b).sub(d));
    }

    function F(
        int256 _x,
        int256 x,
        int256 y
    ) internal pure returns (int256 _y) {
        int256 k;
        int256 c;
        {
            // u = x + ay, v = y + ax
            int256 u = x.add(y.mul(int256(amplifier)).div(1e18));
            int256 v = y.add(x.mul(int256(amplifier)).div(1e18));
            k = u.mul(v); // k = u * v
            c = _x.mul(_x).sub(k.mul(1e18).div(int256(amplifier))); // c = x^2 - k/a
        }

        int256 cst = int256(amplifier).add(1e36.div(int256(amplifier))); // a + 1/a
        int256 b = _x.mul(cst).div(1e18);

        // y^2 + by + c = 0
        // D = b^2 - 4c
        // _y = (-b + sqrt(D)) / 2

        int256 D = b.mul(b).sub(c.mul(4));

        require(D >= 0, "no root");

        _y = (-b).add(D.sqrt()).div(2);
    }

    function getInputPrice(
        uint256 input,
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 d
    ) public pure returns (uint256) {
        int256 x = int256(a).sub(int256(b));
        int256 y = int256(c).sub(int256(d));
        int256 _x = x.add(int256(input));

        int256 _y = F(_x, x, y);

        return uint256(y.sub(_y));
    }

    function getOutputPrice(
        uint256 output,
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 d
    ) public pure returns (uint256) {
        int256 x = int256(a).sub(int256(b));
        int256 y = int256(c).sub(int256(d));
        int256 _y = y.sub(int256(output));

        int256 _x = F(_y, y, x);

        return uint256(_x.sub(x));
    }

    function rate() public pure returns (uint256) {
        return 1e12;
    }

    /***********************************|
    |        Exchange Functions         |
    |__________________________________*/

    function calcFee(
        uint256 input,
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 d
    ) internal {
        if (protocolFee > 0) {
            uint256 _fee = input
                .mul(protocolFee)
                .mul(_totalSupply)
                .div(1e18)
                .div(a.add(c).sub(b).sub(d));
            _mint(vault, _fee);
        }
    }

    function dai2usdcIn(
        uint256 input,
        uint256 min_output,
        uint256 deadline
    ) external returns (uint256) {
        require(block.timestamp <= deadline, "EXPIRED");
        (uint256 a, uint256 b) = getDaiBalance();
        (uint256 c, uint256 d) = getUSDCBalance();

        uint256 output = getInputPrice(input.mul(fee).div(1e18), a, b, c, d);
        securityCheck(input, output, a, b, c, d);
        output = output.div(rate());
        require(output >= min_output, "SLIPPAGE_DETECTED");

        calcFee(input, a, b, c, d);

        doTransferIn(Dai, cDai, b, msg.sender, input);
        doTransferOut(USDC, cUSDC, c.div(rate()), msg.sender, output);

        emit Purchases(msg.sender, address(Dai), input, address(USDC), output);

        return output;
    }

    function usdc2daiIn(
        uint256 input,
        uint256 min_output,
        uint256 deadline
    ) external returns (uint256) {
        require(block.timestamp <= deadline, "EXPIRED");
        (uint256 a, uint256 b) = getDaiBalance();
        (uint256 c, uint256 d) = getUSDCBalance();

        uint256 output = getInputPrice(input.mul(fee).div(1e6), c, d, a, b); // input * rate() * fee / 1e18
        securityCheck(input.mul(rate()), output, c, d, a, b);
        require(output >= min_output, "SLIPPAGE_DETECTED");

        calcFee(input.mul(rate()), a, b, c, d);

        doTransferIn(USDC, cUSDC, d.div(rate()), msg.sender, input);
        doTransferOut(Dai, cDai, a, msg.sender, output);

        emit Purchases(msg.sender, address(USDC), input, address(Dai), output);

        return output;
    }

    function dai2usdcOut(
        uint256 max_input,
        uint256 output,
        uint256 deadline
    ) external returns (uint256) {
        require(block.timestamp <= deadline, "EXPIRED");
        (uint256 a, uint256 b) = getDaiBalance();
        (uint256 c, uint256 d) = getUSDCBalance();

        uint256 input = getOutputPrice(output.mul(rate()), a, b, c, d);
        securityCheck(input, output.mul(rate()), a, b, c, d);
        input = input.mul(1e18).divCeil(fee);
        require(input <= max_input, "SLIPPAGE_DETECTED");

        calcFee(input, a, b, c, d);

        doTransferIn(Dai, cDai, b, msg.sender, input);
        doTransferOut(USDC, cUSDC, c.div(rate()), msg.sender, output);

        emit Purchases(msg.sender, address(Dai), input, address(USDC), output);

        return input;
    }

    function usdc2daiOut(
        uint256 max_input,
        uint256 output,
        uint256 deadline
    ) external returns (uint256) {
        require(block.timestamp <= deadline, "EXPIRED");
        (uint256 a, uint256 b) = getDaiBalance();
        (uint256 c, uint256 d) = getUSDCBalance();

        uint256 input = getOutputPrice(output, c, d, a, b);
        securityCheck(input, output, c, d, a, b);
        input = input.mul(1e6).divCeil(fee); // input * 1e18 / fee / 1e12
        require(input <= max_input, "SLIPPAGE_DETECTED");

        calcFee(input.mul(rate()), a, b, c, d);

        doTransferIn(USDC, cUSDC, d.div(rate()), msg.sender, input);
        doTransferOut(Dai, cDai, a, msg.sender, output);

        emit Purchases(msg.sender, address(USDC), input, address(Dai), output);

        return input;
    }

    function doTransferIn(
        ERC20 token,
        CERC20 ctoken,
        uint256 debt,
        address from,
        uint256 amount
    ) internal {
        require(token.transferFrom(from, address(this), amount));

        if (debt > 0) {
            if (debt >= amount) {
                require(
                    ctoken.repayBorrow(amount) == 0,
                    "ctoken.repayBorrow failed"
                );
            } else {
                require(
                    ctoken.repayBorrow(debt) == 0,
                    "ctoken.repayBorrow failed"
                );
                require(
                    ctoken.mint(amount.sub(debt)) == 0,
                    "ctoken.mint failed"
                );
            }
        } else {
            require(ctoken.mint(amount) == 0, "ctoken.mint failed");
        }
    }

    function doTransferOut(
        ERC20 token,
        CERC20 ctoken,
        uint256 balance,
        address to,
        uint256 amount
    ) internal {
        if (balance >= amount) {
            require(
                ctoken.redeemUnderlying(amount) == 0,
                "ctoken.redeemUnderlying failed"
            );
        } else {
            if (balance == 0) {
                require(ctoken.borrow(amount) == 0, "ctoken.borrow failed");
            } else {
                require(
                    ctoken.redeemUnderlying(balance) == 0,
                    "ctoken.redeemUnderlying failed"
                );
                require(
                    ctoken.borrow(amount.sub(balance)) == 0,
                    "ctoken.borrow failed"
                );
            }
        }

        require(token.transfer(to, amount));
    }

    function securityCheck(
        uint256 input,
        uint256 output,
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 d
    ) internal pure {
        if (c < output.add(d))
            require(
                output.add(d).sub(c).mul(100) < input.add(a).sub(b).mul(62),
                "DEBT_TOO_MUCH"
            ); // debt/collateral < 62%
    }

    /***********************************|
    |        Liquidity Functions        |
    |__________________________________*/

    function addLiquidity(
        uint256 share,
        uint256[4] calldata tokens
    )
        external
        returns (
            uint256 dai_in,
            uint256 dai_out,
            uint256 usdc_in,
            uint256 usdc_out
        )
    {
        require(share >= 1e15, "INVALID_ARGUMENT"); // 1000 * rate()

        collectComp();

        if (_totalSupply > 0) {
            (uint256 a, uint256 b) = getDaiBalance();
            (uint256 c, uint256 d) = getUSDCBalance();

            dai_in = share.mul(a).divCeil(_totalSupply);
            dai_out = share.mul(b).div(_totalSupply);
            usdc_in = share.mul(c).divCeil(_totalSupply.mul(rate()));
            usdc_out = share.mul(d).div(_totalSupply.mul(rate()));
            require(
                dai_in <= tokens[0] &&
                    dai_out >= tokens[1] &&
                    usdc_in <= tokens[2] &&
                    usdc_out >= tokens[3],
                "SLIPPAGE_DETECTED"
            );

            _mint(msg.sender, share);

            if (dai_in > 0) doTransferIn(Dai, cDai, b, msg.sender, dai_in);
            if (usdc_in > 0)
                doTransferIn(USDC, cUSDC, d.div(rate()), msg.sender, usdc_in);
            if (dai_out > 0) doTransferOut(Dai, cDai, a, msg.sender, dai_out);
            if (usdc_out > 0)
                doTransferOut(USDC, cUSDC, c.div(rate()), msg.sender, usdc_out);

            int256 dai_amount = int256(dai_in).sub(int256(dai_out));
            int256 usdc_amount = int256(usdc_in).sub(int256(usdc_out));

            emit AddLiquidity(msg.sender, share, dai_amount, usdc_amount);
            return (dai_in, dai_out, usdc_in, usdc_out);
        } else {
            uint256 dai_amount = share.divCeil(2);
            uint256 usdc_amount = share.divCeil(rate().mul(2));

            _mint(msg.sender, share);
            doTransferIn(Dai, cDai, 0, msg.sender, dai_amount);
            doTransferIn(USDC, cUSDC, 0, msg.sender, usdc_amount);

            emit AddLiquidity(
                msg.sender,
                share,
                int256(dai_amount),
                int256(usdc_amount)
            );
            return (dai_amount, 0, usdc_amount, 0);
        }
    }

    function removeLiquidity(
        uint256 share,
        uint256[4] calldata tokens
    )
        external
        returns (
            uint256 dai_in,
            uint256 dai_out,
            uint256 usdc_in,
            uint256 usdc_out
        )
    {
        require(share > 0, "INVALID_ARGUMENT");

        collectComp();

        (uint256 a, uint256 b) = getDaiBalance();
        (uint256 c, uint256 d) = getUSDCBalance();

        dai_out = share.mul(a).div(_totalSupply);
        dai_in = share.mul(b).divCeil(_totalSupply);
        usdc_out = share.mul(c).div(_totalSupply.mul(rate()));
        usdc_in = share.mul(d).divCeil(_totalSupply.mul(rate()));
        require(
            dai_in <= tokens[0] &&
                dai_out >= tokens[1] &&
                usdc_in <= tokens[2] &&
                usdc_out >= tokens[3],
            "SLIPPAGE_DETECTED"
        );

        _burn(msg.sender, share);

        if (dai_in > 0) doTransferIn(Dai, cDai, b, msg.sender, dai_in);
        if (usdc_in > 0)
            doTransferIn(USDC, cUSDC, d.div(rate()), msg.sender, usdc_in);
        if (dai_out > 0) doTransferOut(Dai, cDai, a, msg.sender, dai_out);
        if (usdc_out > 0)
            doTransferOut(USDC, cUSDC, c.div(rate()), msg.sender, usdc_out);

        int256 dai_amount = int256(dai_out).sub(int256(dai_in));
        int256 usdc_amount = int256(usdc_out).sub(int256(usdc_in));

        emit RemoveLiquidity(msg.sender, share, dai_amount, usdc_amount);

        return (dai_in, dai_out, usdc_in, usdc_out);
    }

    /***********************************|
    |           Collect Comp            |
    |__________________________________*/

    function collectComp() public {
        uint256 _comp = Comp.balanceOf(address(this));
        if (_comp == 0) return;

        (uint256 a, uint256 b) = getDaiBalance();
        (uint256 c, uint256 d) = getUSDCBalance();

        bool isDai = a.add(d) > c.add(b);

        address[] memory path = new address[](3);
        path[0] = address(Comp);
        path[1] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; //weth
        path[2] = isDai ? address(Dai) : address(USDC);
        uint256[] memory amounts = uniswap.swapExactTokensForTokens(
            _comp,
            0,
            path,
            address(this),
            now
        );

        if (isDai) require(cDai.mint(amounts[2]) == 0, "ctoken.mint failed");
        else require(cUSDC.mint(amounts[2]) == 0, "ctoken.mint failed");
    }
}
