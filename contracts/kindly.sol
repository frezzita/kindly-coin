// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.3;

import './Ownable.sol';
import './libraries/SafeMath.sol';
import './libraries/Address.sol';
import './interfaces/IERC20.sol';

contract Kindly is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    mapping (address => uint256) private _rOwned;
    mapping (address => uint256) private _tOwned;
    mapping (address => mapping (address => uint256)) private _allowances;

    mapping (address => bool) private _isExcludedFromFee;

    mapping (address => bool) private _isExcluded;
    address[] private _excluded;

    struct ValuesResult {
        uint256 tTransferAmount;
        uint256 tFee;
        uint256 tLiquidity;
        uint256 tCharity;
        uint256 tDev;
        uint256 tLiquidityWallet;
        uint256 rAmount;
        uint256 rTransferAmount;
        uint256 rFee;
        uint256 rLiquidity;
        uint256 rCharity;
        uint256 rDev;
        uint256 rLiquidityWallet;
    }

    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal = 108000 * 10**6 * 10**18;
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 private _tFeeTotal;

    string private _name = "Kindly";
    string private _symbol = "KINDLY";
    uint8 private _decimals = 18;
    
    // fees
    uint256 public _taxFee = 1;
    uint256 private _previousTaxFee = _taxFee;
    
    uint256 public _charityFee = 5;
    uint256 private _previousCharityFee = _charityFee;

    uint256 public _devFee = 1;
    uint256 private _previousDevFee = _devFee;

    uint256 public _liquidityWalletFee = 1;
    uint256 private _previousliquidityWalletFee = _liquidityWalletFee;

    uint256 public _liquidityFee = 0;
    uint256 private _previousLiquidityFee = _liquidityFee;

    uint256 public _maxTxAmount = 540 * 10**6 * 10**18; // 0.005
    
    constructor (address payable charityAddress, address payable devAddress, address payable liquidityWalletAddress) {
        _rOwned[owner()] = _rTotal;

        // exclude owner and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;

        setCharityAddress(charityAddress);
        setDevAddress(devAddress);
        setLiquidityWalletAddress(liquidityWalletAddress);
        
        emit Transfer(address(0), owner(), _tTotal);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function totalRSupply() public view onlyOwner() returns (uint256) {
        return _rTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function balanceOfT(address account) public view onlyOwner() returns (uint256) {
        return _tOwned[account];
    }

    function balanceOfR(address account) public view onlyOwner() returns (uint256) {
        return _rOwned[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    function deliver(uint256 tAmount) public {
        address sender = _msgSender();
        require(!_isExcluded[sender], "Excluded addresses cannot call this function");
        (uint256 rAmount,,,,,,,,) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rTotal = _rTotal.sub(rAmount);
        _tFeeTotal = _tFeeTotal.add(tAmount);
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) public view returns(uint256) {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 rAmount,,,,,,,,) = _getValues(tAmount);
            return rAmount;
        } else {
            (,uint256 rTransferAmount,,,,,,,) = _getValues(tAmount);
            return rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate =  _getRate();
        return rAmount.div(currentRate);
    }

    function excludeFromReward(address account) public override onlyOwner() {
        // require(account != 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, 'We can not exclude Uniswap router.');
        require(!_isExcluded[account], "Account is already excluded");
        if(_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function includeInReward(address account) external onlyOwner() {
        require(_isExcluded[account], "Account is already included");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }
    
    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }
    
    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }
    
    function setTaxFeePercent(uint256 taxFee) external onlyOwner() {
        require(taxFee <= 1, "Cannot set percentage over 1%");
        _taxFee = taxFee;
    }

    function setCharityFeePercent(uint256 charityFee) external onlyOwner() {
        require(charityFee <= 5, "Cannot set percentage over 5%");
        _charityFee = charityFee;
    }

    function setDevFeePercent(uint256 devFee) external onlyOwner() {
        require(devFee <= 1, "Cannot set percentage over 1%");
        _devFee = devFee;
    }
    
    function setLiquidityWalletFeePercent(uint256 liquidityWalletFee) external onlyOwner() {
        require(liquidityWalletFee <= 1, "Cannot set percentage over 1%");
        _liquidityWalletFee = liquidityWalletFee;
    }

    function setLiquidityFeePercent(uint256 liquidityFee) external onlyOwner() {
        require(liquidityFee <= 1, "Cannot set percentage over 1%");
        _liquidityFee = liquidityFee;
    }
   
    function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner() {
        _maxTxAmount = _tTotal.mul(maxTxPercent).div(
            10**2
        );
    }
    
    // to recieve ETH from uniswapV2Router when swaping
    receive() external payable {}

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _getValues(uint256 tAmount) private view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        ValuesResult memory valuesResult = ValuesResult(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);

        _getTValues(tAmount, valuesResult);
        _getRValues(tAmount, valuesResult, _getRate());

        return (valuesResult.rAmount, valuesResult.rTransferAmount, valuesResult.rFee, valuesResult.tTransferAmount, valuesResult.tFee, valuesResult.tLiquidity, valuesResult.tCharity, valuesResult.tDev, valuesResult.tLiquidityWallet);
    }

    function _getTValues(uint256 tAmount, ValuesResult memory valuesResult) private view returns (ValuesResult memory) {
        {
            uint256 tFee = calculateTaxFee(tAmount);
            valuesResult.tFee = tFee;
        }
        {
            uint256 tLiquidity = calculateLiquidityFee(tAmount);
            valuesResult.tLiquidity = tLiquidity;
        }
        {
            uint256 tCharity = calculateCharityFee(tAmount);
            valuesResult.tCharity = tCharity;
        }
        {
            uint256 tDev = calculateDevFee(tAmount);
            valuesResult.tDev = tDev;
        }
        {
            uint256 tLiquidityWallet = calculateLiquidityWalletFee(tAmount);
            valuesResult.tLiquidityWallet = tLiquidityWallet;
        }

        valuesResult.tTransferAmount = tAmount.sub(valuesResult.tFee).sub(valuesResult.tLiquidity).sub(valuesResult.tCharity).sub(valuesResult.tDev).sub(valuesResult.tLiquidityWallet);
        return valuesResult;
    }

    function _getRValues(uint256 tAmount, ValuesResult memory valuesResult, uint256 currentRate) private pure returns (ValuesResult memory) {
        {
            uint256 rAmount = tAmount.mul(currentRate);
            valuesResult.rAmount = rAmount;
        }
        {
            uint256 rFee = valuesResult.tFee.mul(currentRate);
            valuesResult.rFee = rFee;
        }
        {
            uint256 rLiquidity = valuesResult.tLiquidity.mul(currentRate);
            valuesResult.rLiquidity = rLiquidity;
        }
        {
            uint256 rCharity = valuesResult.tCharity.mul(currentRate);
            valuesResult.rCharity = rCharity;
        }
        {
            uint256 rDev = valuesResult.tDev.mul(currentRate);
            valuesResult.rDev = rDev;
        }
        {
            uint256 rLiquidityWallet = valuesResult.tLiquidityWallet.mul(currentRate);
            valuesResult.rLiquidityWallet = rLiquidityWallet;
        }

        valuesResult.rTransferAmount = valuesResult.rAmount.sub(valuesResult.rFee).sub(valuesResult.rLiquidity).sub(valuesResult.rCharity).sub(valuesResult.rDev).sub(valuesResult.rLiquidityWallet);
        return (valuesResult);
    }

    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;      
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }
    
    function _takeLiquidity(uint256 tLiquidity) private {
        uint256 currentRate =  _getRate();
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        _rOwned[address(this)] = _rOwned[address(this)].add(rLiquidity);
        if(_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)].add(tLiquidity);
    }
    
    function _takeCharity(uint256 tCharity) private {
        uint256 currentRate =  _getRate();
        uint256 rCharity = tCharity.mul(currentRate);
        _rOwned[charity()] = _rOwned[charity()].add(rCharity);
        if(_isExcluded[charity()])
            _tOwned[charity()] = _tOwned[charity()].add(tCharity);
    }

    function _takeDev(uint256 tDev) private {
        uint256 currentRate =  _getRate();
        uint256 rDev = tDev.mul(currentRate);
        _rOwned[dev()] = _rOwned[dev()].add(rDev);
        if(_isExcluded[dev()])
            _tOwned[dev()] = _tOwned[dev()].add(tDev);
    }
    
    function _takeLiquidityWallet(uint256 tLiquidityWallet) private {
        uint256 currentRate =  _getRate();
        uint256 rLiquidityWallet = tLiquidityWallet.mul(currentRate);
        _rOwned[liquidityWallet()] = _rOwned[liquidityWallet()].add(rLiquidityWallet);
        if(_isExcluded[liquidityWallet()])
            _tOwned[liquidityWallet()] = _tOwned[liquidityWallet()].add(tLiquidityWallet);
    }

    function calculateTaxFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_taxFee).div(
            10**2
        );
    }

    function calculateCharityFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_charityFee).div(
            10**2
        );
    }

    function calculateDevFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_devFee).div(
            10**2
        );
    }

    function calculateLiquidityWalletFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_liquidityWalletFee).div(
            10**2
        );
    }

    function calculateLiquidityFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_liquidityFee).div(
            10**2
        );
    }
    
    function removeAllFee() private {
        if(_taxFee == 0 && _liquidityFee == 0) return;
        
        _previousTaxFee = _taxFee;
        _previousCharityFee = _charityFee;
        _previousDevFee = _devFee;
        _previousliquidityWalletFee = _liquidityWalletFee;
        _previousLiquidityFee = _liquidityFee;
        
        _taxFee = 0;
        _charityFee = 0;
        _devFee = 0;
        _liquidityWalletFee = 0;
        _liquidityFee = 0;
    }
    
    function restoreAllFee() private {
        _taxFee = _previousTaxFee;
        _charityFee = _previousCharityFee;
        _devFee = _previousDevFee;
        _liquidityWalletFee = _previousliquidityWalletFee;
        _liquidityFee = _previousLiquidityFee;
    }
    
    function isExcludedFromFee(address account) public view returns(bool) {
        return _isExcludedFromFee[account];
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
    * TRANSFER
    */
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        if(from != owner() && to != owner())
            require(amount <= _maxTxAmount, "Transfer amount exceeds the maxTxAmount.");
        
        //indicates if fee should be deducted from transfer
        bool takeFee = true;
        
        //if any account belongs to _isExcludedFromFee account then remove the fee
        if(_isExcludedFromFee[from] || _isExcludedFromFee[to]){
            takeFee = false;
        }
        
        //transfer amount, it will take tax, burn, liquidity fee
        _tokenTransfer(from,to,amount,takeFee);
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(address sender, address recipient, uint256 amount,bool takeFee) private {
        if(!takeFee)
            removeAllFee();
        
        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferStandard(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }
        
        if(!takeFee)
            restoreAllFee();
    }

    function _transferStandard(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity, uint256 tCharity, uint256 tDev, uint256 tLiquidityWallet) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _takeCharity(tCharity);
        _takeDev(tDev);
        _takeLiquidityWallet(tLiquidityWallet);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferToExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity, uint256 tCharity, uint256 tDev, uint256 tLiquidityWallet) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);           
        _takeLiquidity(tLiquidity);
        _takeCharity(tCharity);
        _takeDev(tDev);
        _takeLiquidityWallet(tLiquidityWallet);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferFromExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity, uint256 tCharity, uint256 tDev, uint256 tLiquidityWallet) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);   
        _takeLiquidity(tLiquidity);
        _takeCharity(tCharity);
        _takeDev(tDev);
        _takeLiquidityWallet(tLiquidityWallet);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferBothExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity, uint256 tCharity, uint256 tDev, uint256 tLiquidityWallet) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);        
        _takeLiquidity(tLiquidity);
        _takeCharity(tCharity);
        _takeDev(tDev);
        _takeLiquidityWallet(tLiquidityWallet);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }
    /**
    * TRANSFER (END)
    */
}