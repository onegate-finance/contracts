pragma solidity 0.5.16;

// Inheritance
import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity-2.3.0/contracts/utils/ReentrancyGuard.sol";

// Libraries
import "openzeppelin-solidity-2.3.0/contracts/math/SafeMath.sol";
import "@uniswap/v2-core/contracts/libraries/Math.sol";
import './SafeToken.sol';

// Internal references
import './interfaces/IBankConfig.sol';
import './interfaces/IPTokenFactory.sol';
import './Goblin.sol';
import "./PToken.sol";

//import 'hardhat/console.sol';

contract Bank is Ownable, ReentrancyGuard {
    /* ========== LIBRARIES ========== */
    using SafeToken for address;
    using SafeMath for uint256;

    /* ========== EVENTS ========== */
    event Deposit(address token, uint256 depositAmount);
    event Withdraw(address token, uint256 withdrawAmount);
    event OpPosition(uint256 indexed id, uint256 debt, uint256 back);
    event Liquidate(uint256 indexed id, address indexed killer, uint256 prize, uint256 left);
    event OperatorChanged(address operatorAddress, address newOperator);

    /* ========== STRUCTURE ========== */
    struct IronBank {
        address tokenAddr;
        address pTokenAddr;
        bool isOpen;
        bool canDeposit;
        bool canWithdraw;
        uint256 totalVal;
        uint256 totalDebt;
        uint256 totalDebtShare;
        uint256 totalReserve;
        uint256 lastInterestTime;
    }

    struct Production {
        address coinToken;
        address currencyToken;
        address borrowToken;
        bool isOpen;
        bool canBorrow;
        address goblin;
        uint256 minDebt;
        uint256 openFactor;
        uint256 liquidateFactor;
    }

    struct Position {
        uint256 productionId;
        address owner;
        uint256 debtShare;
    }

    IBankConfig public config;
    IPTokenFactory public factory;

    mapping(address => IronBank) public banks;

    mapping(uint256 => Production) public productions;
    uint256 public currentPid = 1;

    mapping(uint256 => Position) public positions;
    uint256 public currentPos = 1;

    address operatorAddress;
    address goldenTouch;

    uint256 goldenTouchSwitch;

    // Require that the caller must be an EOA account to avoid flash loans.
    modifier onlyEOA() {
        require(msg.sender == tx.origin, 'not eoa');
        _;
    }

    // Require that the caller must be an operator account.
    modifier onlyOperator() {
        require(msg.sender == operatorAddress, 'not operator');
        _;
    }

    constructor(
        address _operatorAddress,
        IPTokenFactory _factory
    ) public {
        operatorAddress = _operatorAddress;
        factory = _factory;
    }

    /* ========== VIEWS ========== */

    // query LPToken Amount Related to the Production Pool
    function lpTotalSupply(uint256 productionId) public view returns (uint256) {
        Production storage prod = productions[productionId];
        return Goblin(prod.goblin).lpTotalSupply();
    }

    // query Position Info
    function positionInfo(uint256 posId) public view returns (uint256, uint256, uint256, address) {
        Position storage pos = positions[posId];
        Production storage prod = productions[pos.productionId];
        return (
        pos.productionId,
        Goblin(prod.goblin).health(posId, prod.borrowToken),
        debtShareToVal(prod.borrowToken, pos.debtShare),
        pos.owner
        );
    }

    // query total token entitled to the token holders.
    function totalToken(address token) public view returns (uint256) {
        IronBank storage bank = banks[token];
        require(bank.isOpen, 'token not exists');
        uint balance = token == address(0)? address(this).balance: SafeToken.myBalance(token);
        balance = bank.totalVal < balance? bank.totalVal: balance;
        return balance.add(bank.totalDebt).sub(bank.totalReserve);
    }

    // convert debtshare to debt value
    function debtShareToVal(address token, uint256 debtShare) public view returns (uint256) {
        IronBank storage bank = banks[token];
        require(bank.isOpen, 'token not exists');
        if (bank.totalDebtShare == 0) return debtShare;
        return debtShare.mul(bank.totalDebt).div(bank.totalDebtShare);
    }

    // convert debt value to debt share
    function debtValToShare(address token, uint256 debtVal) public view returns (uint256) {
        IronBank storage bank = banks[token];
        require(bank.isOpen, 'token not exists');
        if (bank.totalDebt == 0) return debtVal;
        return debtVal.mul(bank.totalDebtShare).div(bank.totalDebt);
    }

    // query Bank Details
    function bankInfo(address token) public view returns (uint256, uint256, uint256, uint256) {
        IronBank storage bank = banks[token];
        uint256 totalDebt = bank.totalDebt;
        uint256 totalBalance = totalToken(token);
        uint256 rateForBorrow = config.getInterestRate(totalDebt, totalBalance);
        uint256 rateForLending;
        if (totalBalance == 0) {
            rateForLending = 0;
        } else {
            rateForLending = rateForBorrow.mul(totalDebt).div(totalBalance);
        }
        return (totalDebt, totalBalance, rateForBorrow, rateForLending);
    }

    /* ========== MODIFIERS ========== */

    // calculate Interest
    function calInterest(address token) public {
        IronBank storage bank = banks[token];
        require(bank.isOpen, 'token not exists');

        if (now > bank.lastInterestTime) {
            uint256 timePast = now.sub(bank.lastInterestTime);
            uint256 totalDebt = bank.totalDebt;
            uint256 totalBalance = totalToken(token);
            // get interest rate base on debt ratio
            uint256 ratePerSec = config.getInterestRate(totalDebt, totalBalance);
            // calculate interest
            uint256 interest = ratePerSec.mul(timePast).mul(totalDebt).div(1e18);
            uint256 toReserve = interest.mul(config.getReserveBps()).div(10000);
            // update record
            bank.totalReserve = bank.totalReserve.add(toReserve);
            bank.totalDebt = bank.totalDebt.add(interest);
            bank.lastInterestTime = now;
        }
    }

    // deposit Money to the IronBank
    function deposit(address token, uint256 amount) external payable nonReentrant {
        IronBank storage bank = banks[token];
        require(bank.isOpen && bank.canDeposit, 'Token not exist or cannot deposit');
        emit Deposit(token, amount);

        calInterest(token);

        if (token == address(0)) {
            amount = msg.value;
        } else {
            SafeToken.safeTransferFrom(token, msg.sender, address(this), amount);
        }

        bank.totalVal = bank.totalVal.add(amount);
        uint256 total = totalToken(token).sub(amount);
        uint256 pTotal = PToken(bank.pTokenAddr).totalSupply();
        // calculate amount of ptoken
        uint256 pAmount = (total == 0 || pTotal == 0) ? amount: amount.mul(pTotal).div(total);
        // mint ptoken
        PToken(bank.pTokenAddr).mint(msg.sender, pAmount);
    }

    // Withdraw Money From IRON BANK with interest
    function withdraw(address token, uint256 pAmount) external nonReentrant {
        IronBank storage bank = banks[token];
        require(bank.isOpen && bank.canWithdraw, 'Token not exist or cannot withdraw');

        calInterest(token);

        uint256 amount = pAmount.mul(totalToken(token)).div(PToken(bank.pTokenAddr).totalSupply());

        bank.totalVal = bank.totalVal.sub(amount);
        PToken(bank.pTokenAddr).burn(msg.sender, pAmount);

        if (token == address(0)) {
            SafeToken.safeTransferETH(msg.sender, amount);
        } else {
            SafeToken.safeTransfer(token, msg.sender, amount);
        }

        emit Withdraw(token, amount);
    }

    // open or close positoin
    function opPosition(
        uint256 posId,
        uint256 pid,
        uint256 borrow,
        bytes calldata data
    ) external payable onlyEOA nonReentrant {
        if (posId == 0) {
            posId = currentPos;
            currentPos ++;
            positions[posId].owner = msg.sender;
            positions[posId].productionId = pid;
        } else {
            require(posId < currentPos, "bad position id");
            require(positions[posId].owner == msg.sender, "not position owner");
            pid = positions[posId].productionId;
        }

        Production storage production = productions[pid];
        require(production.isOpen, 'Production not exists');
        require(borrow == 0 || production.canBorrow, "Production can not borrow");

        calInterest(production.borrowToken);

        uint256 debt = _removeDebt(positions[posId], production).add(borrow);
        bool isBorrowHT = production.borrowToken == address(0);
        uint256 sendHT = msg.value;
        uint256 beforeToken;

        if (isBorrowHT) {
            sendHT = sendHT.add(borrow);
            require(sendHT <= address(this).balance && debt <= banks[production.borrowToken].totalVal, "insufficient HT in the bank");
            beforeToken = address(this).balance.sub(sendHT);
        } else {
            beforeToken = SafeToken.myBalance(production.borrowToken);
            require(borrow <= beforeToken && debt <= banks[production.borrowToken].totalVal, "insufficient borrowToken in the bank");
            beforeToken = beforeToken.sub(borrow);
            SafeToken.safeApprove(production.borrowToken, production.goblin, borrow);
        }

        Goblin(production.goblin).work.value(sendHT)(posId, msg.sender, production.borrowToken, borrow, debt, data);

        uint256 backToken = isBorrowHT ? (address(this).balance.sub(beforeToken)) :
        SafeToken.myBalance(production.borrowToken).sub(beforeToken);

        if(backToken > debt) {
            backToken = backToken.sub(debt);
            debt = 0;
            isBorrowHT ? SafeToken.safeTransferETH(msg.sender, backToken):
            SafeToken.safeTransfer(production.borrowToken, msg.sender, backToken);
        } else if (debt > backToken) {
            debt = debt.sub(backToken);
            backToken = 0;
            require(debt >= production.minDebt, "too small debt size");
            uint256 health = Goblin(production.goblin).health(posId, production.borrowToken);
            require(health.mul(production.openFactor) >= debt.mul(10000), "bad work factor");
            _addDebt(positions[posId], production, debt);
        }
        emit OpPosition(posId, debt, backToken);
    }

    // liquidate
    function liquidate(uint256 posId) external onlyEOA nonReentrant {

        if (goldenTouchSwitch != 0) {
            require(msg.sender == goldenTouch, "goldenTouch Mode Activate");
        }

        Position storage pos = positions[posId];
        require(pos.debtShare > 0, "no debt");
        Production storage production = productions[pos.productionId];

        uint256 debt = _removeDebt(pos, production);

        uint256 health = Goblin(production.goblin).health(posId, production.borrowToken);
        require(health.mul(production.liquidateFactor) < debt.mul(10000), "can't liquidate");

        bool isHT = production.borrowToken == address(0);
        uint256 before = isHT ? address(this).balance: SafeToken.myBalance(production.borrowToken);

        Goblin(production.goblin).liquidate(posId, production.borrowToken, pos.owner);

        uint256 back = isHT ? address(this).balance: SafeToken.myBalance(production.borrowToken);
        back = back.sub(before);

        uint256 prize = back.mul(config.getLiquidateBps()).div(10000);
        uint256 rest = back.sub(prize);
        uint256 left;

        if (prize > 0) {
            isHT ? SafeToken.safeTransferETH(msg.sender, prize): SafeToken.safeTransfer(production.borrowToken, msg.sender, prize);
        }
        if (rest > debt) {
            left = rest.sub(debt);
            isHT ? SafeToken.safeTransferETH(pos.owner, left): SafeToken.safeTransfer(production.borrowToken, pos.owner, left);
        } else {
          banks[production.borrowToken].totalVal = banks[production.borrowToken].totalVal.sub(debt).add(rest);
        }
        emit Liquidate(posId, msg.sender, prize, left);
    }

    // Internal function to add the given debt value to the given position.
    function _addDebt(Position storage pos, Production storage production, uint256 debtVal) internal {
        if (debtVal == 0) {
            return;
        }
        IronBank storage bank = banks[production.borrowToken];
        uint256 debtShare = debtValToShare(production.borrowToken, debtVal);
        pos.debtShare = pos.debtShare.add(debtShare);
        bank.totalVal = bank.totalVal.sub(debtVal);
        bank.totalDebtShare = bank.totalDebtShare.add(debtShare);
        bank.totalDebt = bank.totalDebt.add(debtVal);
    }

    // Internal function to clear the debt of the given position. Return the debt value.
    function _removeDebt(Position storage pos, Production storage production) internal returns (uint256) {
        IronBank storage bank = banks[production.borrowToken];

        uint256 debtShare = pos.debtShare;
        if (debtShare > 0) {
            uint256 debtVal = debtShareToVal(production.borrowToken, debtShare);
            pos.debtShare = 0;
            bank.totalVal = bank.totalVal.add(debtVal);
            bank.totalDebtShare = bank.totalDebtShare.sub(debtShare);
            bank.totalDebt = bank.totalDebt.sub(debtVal);
            return debtVal;
        } else {
            return 0;
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    // Set new configurator address. Must only be called by operator.
    function updateConfig(IBankConfig _config) external onlyOperator {
        config = _config;
    }

    // Add new bank to the system. Must only by operator.
    function addBank(address token, string calldata _symbol) external onlyOperator {
        IronBank storage bank = banks[token];
        require(!bank.isOpen, 'token already exists');
        bank.isOpen = true;
        address pToken = factory.genPToken(_symbol);
        bank.tokenAddr = token;
        bank.pTokenAddr = pToken;
        bank.canDeposit = true;
        bank.canWithdraw = true;
        bank.totalVal = 0;
        bank.totalDebt = 0;
        bank.totalDebtShare = 0;
        bank.totalReserve = 0;
        bank.lastInterestTime = now;
    }

    // Change the statue of one bank. Must only be called by operator.
    function updateBank(address token, bool canDeposit, bool canWithdraw) external onlyOperator {
        IronBank storage bank = banks[token];
        require(bank.isOpen, 'token not exists');
        bank.canDeposit = canDeposit;
        bank.canWithdraw = canWithdraw;
    }

    // Add or Change Production state. Must only be called by operator.
    function opProduction(
        uint256 pid,
        bool isOpen,
        bool canBorrow,
        address coinToken,
        address currencyToken,
        address borrowToken,
        address goblin,
        uint256 minDebt,
        uint256 openFactor,
        uint256 liquidateFactor
    ) external onlyOperator {
        if(pid == 0){
            pid = currentPid;
            currentPid ++;
        } else {
            require(pid < currentPid, "bad production id");
        }
        Production storage production = productions[pid];
        production.isOpen = isOpen;
        production.canBorrow = canBorrow;
        production.coinToken = coinToken;
        production.currencyToken = currencyToken;
        production.borrowToken = borrowToken;
        production.goblin = goblin;
        production.minDebt = minDebt;
        production.openFactor = openFactor;
        production.liquidateFactor = liquidateFactor;
    }

    // Harvest only owner. Must not exceed `reservePool`.
    function withdrawReserve(address token, address to, uint256 value) external onlyOwner nonReentrant {
        IronBank storage bank = banks[token];
        require(bank.isOpen, 'token not exists');

        uint balance = token == address(0)? address(this).balance: SafeToken.myBalance(token);
        if(balance >= bank.totalVal.add(value)) {

        } else {
            bank.totalReserve = bank.totalReserve.sub(value);
            bank.totalVal = bank.totalVal.sub(value);
        }

        if (token == address(0)) {
            SafeToken.safeTransferETH(to, value);
        } else {
            SafeToken.safeTransfer(token, to, value);
        }
    }

    // Change Operator address only owner
    function changeOperator(address newOperator) public onlyOwner nonReentrant {
        require(newOperator != address(0), "new operator address is the zero address");
        emit OperatorChanged(operatorAddress, newOperator);
        operatorAddress = newOperator;
    }

    function setGoldenTouchAddress(address newGoldenTouch) public onlyOwner nonReentrant {
        require(newGoldenTouch != address(0), "new GoldenTouch address is the zero address");
        goldenTouch = newGoldenTouch;
    }

    function goldenTouchController(uint256 status) public onlyOwner nonReentrant {
        require (goldenTouch != address(0), "set golden touch address first");
        goldenTouchSwitch = status; // != 0 for activate status
    }

    // Fallback function to accept HT. Goblins will send HT back the pool.
    function() external payable {}
}
