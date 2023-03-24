// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// We are using ERC20 because we need to mint and creatw Crypto Dev LP tokens
contract Exchange is ERC20 {
    address public cryptoDevTokenAddress;

    constructor(address _CryptoDevtoken) ERC20("CryptoDev LP Token", "CDLP") {
        require(
            _CryptoDevtoken != address(0),
            "Token address passed is a null address"
        );
        cryptoDevTokenAddress = _CryptoDevtoken;
    }

    /**
     * @dev Returns the amount of CDLP held by the contract (reserves)
     * Since eth reseves can be found using `address(this).balance`, we are only going to check for CryptoDev Tokens reserves.
     * Since the contract is an ERC20, we can use balanceOf to check the balance.
     */
    function getReserve() public view returns (uint) {
        return ERC20(cryptoDevTokenAddress).balanceOf(address(this));
    }

    /**
     * @dev Adds liquidity in the form of ETH and CryptoDev Tokens to the exchange
     * If the cryptoDev token reserve is not 0, we have to maintain the ratio as a constant
     * The amount of LP tokens minted to the user are proportional to the ETH supplied by the user
     */
    function addLiquidity(uint _amount) public payable returns (uint) {
        uint liquidity;
        uint ethBalance = address(this).balance;
        uint cryptoDevTokenReserve = getReserve();
        ERC20 cryptoDevToken = ERC20(cryptoDevTokenAddress);

        // If the reserve is empty, there is no ratio.
        if (cryptoDevTokenReserve == 0) {
            cryptoDevToken.transferFrom(msg.sender, address(this), _amount);
            // Since it is the first user, liquidity is equal to the ETH balance provided
            liquidity = ethBalance;
            _mint(msg.sender, liquidity); //ERC20 function to mint ERC20 coins
        } else {
            /*
            If the reserve is not empty, intake any user supplied value for
            `Ether` and determine according to the ratio how many `Crypto Dev` tokens
            need to be supplied to prevent any large price impacts because of the additional
            liquidity
        */
            uint ethReserve = ethBalance - msg.value;
            uint cryptoDevTokenAmount = (msg.value * cryptoDevTokenReserve) /
                ethReserve;
            require(
                _amount >= cryptoDevTokenAmount,
                "Amount of tokens sent is less than the minimum tokens required."
            );
            cryptoDevToken.transferFrom(
                msg.sender,
                address(this),
                cryptoDevTokenAmount
            );
            // The amount of LP tokens that would be sent to the user should be proportional to the liquidity of ether added by the user
            liquidity = (totalSupply() * msg.value) / ethReserve;
            _mint(msg.sender, liquidity);
        }
        return liquidity;
    }

    /**
     * @dev Returns the amount of ETH/Crypto Dev tokans that would be returned to the user's wallet after removing liquidity.
     */
    function removeLiquidity(uint _amount) public returns (uint, uint) {
        require(_amount > 0, "_amount should be greater than zero");
        uint ethReserve = address(this).balance;
        uint _totalSupply = totalSupply();
        // Calculate how many tokens would be sent back to the user
        uint ethAmount = (ethReserve * _amount) / _totalSupply;
        uint cryptoDevTokenAmount = (getReserve() * _amount) / _totalSupply;
        // Remove liquidity
        _burn(msg.sender, _amount);
        // Transfer `ethAmount` to user's wallet
        payable(msg.sender).transfer(ethAmount);
        // Transfer `cryptoDevTokenAmount` to user's wallet
        ERC20(cryptoDevTokenAddress).transfer(msg.sender, cryptoDevTokenAmount);
        return (ethAmount, cryptoDevTokenAmount);
    }

    /**
     * @dev Retuens the amount of ETH/Crypto Dev Tokens returned to a user during a swap depending on their input amount.
     */
    function getAmountOfTokens(
        uint256 inputAmount,
        uint256 inputReserve,
        uint256 outputReserve
    ) public pure returns (uint256) {
        require(inputReserve > 0 && outputReserve > 0, "invalid reserves");
        // get a 1% transaction fee
        uint256 inputAmountWithFee = inputAmount * 99;
        // Because we need to follow the concept of `XY = K` curve
        // We need to make sure (x + Δx) * (y - Δy) = x * y
        // So the final formula is Δy = (y * Δx) / (x + Δx)
        // Δy in our case is `tokens to be received`
        // Δx = ((input amount)*99)/100, x = inputReserve, y = outputReserve
        // So by putting the values in the formulae you can get the numerator and denominator
        uint256 numerator = inputAmountWithFee * outputReserve;
        uint256 denominator = (inputReserve * 100) + inputAmountWithFee;
        return numerator / denominator;
    }

    /**
     * @dev Swaps ETH for CryptoDev Tokens
     */
    function ethToCryptoDevToken(uint _mintTokens) public payable {
        uint256 tokenReserve = getReserve();
        // Get the amount of CryptoDev Tokens that would be returnd after the swap.
        // To get the actual input reserve, use address(this).balance - msg.value
        uint256 tokensBought = getAmountOfTokens(
            msg.value,
            address(this).balance - msg.value,
            tokenReserve
        );
        require(tokensBought >= _mintTokens, "insufficient output amount");
        // Transfer the CryptoDev Tokens to the user's wallet
        ERC20(cryptoDevTokenAddress).transfer(msg.sender, tokensBought);
    }

    /**
     * @dev Swaps CryptoDev Tokens for Eth
     */
    function cryptoDevTokenToEth(uint _tokensSold, uint _minEth) public {
        uint256 tokenReserve = getReserve();
        uint256 ethBought = getAmountOfTokens(
            _tokensSold,
            tokenReserve,
            address(this).balance
        );
        require(ethBought >= _minEth, "insufficient output amount");
        // Transfer `CryptoDev` tokens from user's address to contract
        ERC20(cryptoDevTokenAddress).transferFrom(
            msg.sender,
            address(this),
            _tokensSold
        );
        // Send the eth bought to the user of the contract.
        payable(msg.sender).transfer(ethBought);
    }
}
