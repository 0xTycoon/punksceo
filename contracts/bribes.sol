// SPDX-License-Identifier:MIT
// Author: 0xTycoon
// Project: Cigarettes (CEO of CryptoPunks)
// Bribe punk holders to become CEOs
pragma solidity ^0.8.11;

import "hardhat/console.sol";

/*

expireAfterSec 7776000 90 days

1. A new bribe is created with the address of who you'd like to become the CEO, plus a minimum bribe amount.
2. Cannot create a new bribe if there is already an existing bribe for that address, either active or partially claimed.
3. 20 bribes active at one time.
4. Others can deposit their own funds into an existing bribe.
Minimum deposit to a bribe must always be 10% of the current CEO asking price.
5. While a bribe is active, no deposits can be withdrawn.
6. A bribe can be deactivated after it had no new deposits in the last 30 days.
When a bribe is deactivated, it gets placed out of the active bribes list and the funds can be withdrawn
Claiming bribes: The CEO who is the subject of a bribe will be able to withdraw from the bribe after claiming it, subject to a linear vesting schedule.
CEO bribe withdrawal vesting: 10% of the total, every 2 epochs
The CEO can only withdraw if they are the CEO.
If the CEO hasn't withdrawn all their funds from the bribe, and their last withdrawal was more than 90 days ago, the bribe funds are forfeited and burned.
Minimum bribe amount is 10% of the current CEO asking price. This value is set by querying the CEO_price value of the CIG token contract. (A requirement is that the CEO must have at least 3600 blocks worth of CIG to be burned)

**/

contract Bribes {

    ICigtoken immutable public cig;
    ICryptoPunks immutable public punks;

    struct Bribe {
        address target;
        uint256 punkID;
        uint256 balance;
        uint256 claimed;
        State state;
        uint256 updatedAt;
    }

    uint256 public minAmount;

    // balance users address => (bribe id => balance)
    mapping(address => mapping(uint256 => uint256)) public deposit;

    mapping(uint256 => Bribe) public bribes;
    uint256[20] public bribesProposed;
    uint256[20] public bribesExpired;
    uint256 public bribeHeight;
    uint256 public acceptedBribe;
    uint256 public immutable durationLimitDays; // how many days the CEO has to claim the bribe
    uint256 private immutable DurationLimitSec; // claimDays expressed in seconds

    enum State {
        Free,
        Proposed,
        Expired,
        Accepted,
        PaidOut, // accepted -> paid out
        Defunct // never been accepted, expired -> defunct
    }

    event New(uint256 id, uint256 amount, address target, uint256 punkID);
    event Burned(uint256 id, uint256 amount); // bribe payment burned
    event Paid(uint256 id, uint256 amount); // bribe payment sent
    event Paidout(uint256 id); // bribe all paidout
    event Accepted(uint256 id); // bribe accepted
    event Expired(uint256 id); // a bribe expired
    event Defunct(uint256 id); // a bribe became defunct
    event Increased(uint256 id, uint256 amount, address indexed from); // increase a bribe
    event Refunded(uint256 id, uint256 amount, address indexed to);
    event MinAmount(uint256 amount);


    /**
    * @param _cig address of the Cigarettes contract
    * @param _punks address of the punks contract
    * @param _claimDays how many days the CEO has to claim the bribe
    * @param _duration, eg 86400 (seconds in a day)
    */
    constructor(
        address _cig,
        address _punks,
        uint256 _claimDays,
        uint256 _duration) {
        cig = ICigtoken(_cig);
        punks = ICryptoPunks(_punks);
        durationLimitDays = _claimDays;
        DurationLimitSec = _duration * _claimDays;
    }

    /**
    * @dev updateMinAmount updates the minimum amount required for a new bribe prorposal
    */
    function updateMinAmount() external {
        require (block.number > cig.taxBurnBlock(), "must be CEO for at least 1 block");
        minAmount = cig.CEO_price() / 10;
        emit MinAmount(minAmount);
    }

    /**
    * @dev newBribe inserts a new bribe
    * @param _target the address to offer the bribe to
    * @param _punkID the punkID to offer the bribe to
    * @param _amount the amount to offer
    * @param _i position in bribesProposed to insert new bribe. Expire any existing bribe
    * @param _j position in expiredBribes to remove and defunct. (do nothing if greater than 20)
    *
    */
    function newBribe(
        address _target,
        uint256 _punkID,
        uint256 _amount,
        uint256 _i,
        uint256 _j
    ) external {
        require (_punkID < 10000, "invalid _punkID");
        require (_target == punks.punkIndexToAddress(_punkID), "punkID not owned by target");
        require(_amount >= minAmount, "not enough cig");
        require(cig.transferFrom(msg.sender, address(this), _amount), "cannot send cig");
        uint256 bribeID;
        // Purge from bribesExpired, defunct _j if expired
        if (_j < 20) {
            bribeID = bribesExpired[_j];
            Bribe storage exb = bribes[bribeID];
            require (exb.state == State.Expired, "must be expired");
            require(_defunct(bribeID, _j, exb) == State.Defunct, "expected _j to defunct");
        }
        // Purge from bribesProposed: if slot not empty, expire old bribe
        bribeID = bribesProposed[_i];
        if (bribeID > 0) {
            Bribe storage ob = bribes[bribeID];
            require (ob.state == State.Proposed, "must be proposed");
            require(_expire(bribeID, _i, _j, ob) == State.Expired, "cannot expire");
        }
        bribeHeight++;
        Bribe storage b = bribes[bribeHeight]; // starts from 1
        b.target = _target;
        b.punkID = _punkID;
        b.balance = _amount;
        b.state = State.Proposed;
        b.updatedAt = block.timestamp;
        bribesProposed[_i] = bribeHeight;
        emit New(bribeID, _amount, _target, _punkID);
    }

    /**
    * @dev increase increase the bribe offering amount
    * @param _i the index of the bribesProposed array that stores the bribeID
    * @param _amount the amount in CIG to be added. Must be at least minAmount
    */
    function increase(uint256 _i, uint256 _amount) external {
        uint256 id = bribesProposed[_i];
        require(id > 0, "no such bribe active");
        require(_amount >= minAmount, "not enough cig");
        Bribe storage b = bribes[id];
        require ((punks.punkIndexToAddress(b.punkID) != b.target)); // ensure target of punk us unchanged
        b.balance += _amount;
        b.updatedAt = block.timestamp;
        require(cig.transferFrom(msg.sender, address(this), _amount), "cannot send cig");
        deposit[msg.sender][id] += _amount; // record deposit
        emit Increased(id, _amount, msg.sender);
    }

    /**
    * @dev expire expires a bribe. The bribe is considered expired if either:
    * 1. Not updated for more than DurationLimitSec
    * 2. The owner of the punk changed (target no longer owns the punk)
    * @param _i the position in bribesProposed to get the id of the bibe to expire
    * @param _j the position in bribesExpired to place the expired bribe to
    */
    function expire(uint256 _i, uint256 _j) external {
        uint256 id = bribesProposed[_i];
        require(id > 0, "no such bribe active");
        Bribe storage b = bribes[id];
        _expire(id, _i, _j, b);
        _sendRefund(id, b);
    }

    /**
    * @dev accept can be called by the existing CEO to accept the bribe
    * @param  _i the index position of the bribe in the bribesProposed list
    * The bribe can be accepted if there is currently no accepted bribe.
    * The CEO must be in charge for at least 1 block, and this is checked by looking at the cig.taxBurnBlock slot

    */
    function accept(uint256 _i) external {
        uint256 id = acceptedBribe;
        address ceo = cig.The_CEO();
        if (id != 0) {
            // payout the existing bribe first
            Bribe storage ab = bribes[id];
            require(_pay(ab, ceo, id) == State.PaidOut, "acceptedBribe not PaidOut");
            // assuming that acceptedBribe will be 0 by now
        }
        require (acceptedBribe == 0, "a bribe is currently accepted");
        id = bribesProposed[_i];
        require(id > 0, "no such bribe active");
        Bribe storage b = bribes[id];
        require (ceo == msg.sender, "must be called by the CEO");
        require (cig.CEO_punk_index() == b.punkID, "punk not CEO");
        require (block.number > cig.taxBurnBlock(), "must be CEO for at least 1 block");
        bribesProposed[_i] = 0; // remove from proposed
        b.state = State.Accepted;
        acceptedBribe = id;
        b.updatedAt = block.timestamp;
        emit Accepted(id);
    }

    /**
    * @dev pay sends the CIG pooled in a bribe to the current target of the bribe
    * checks to make sure it can be called once per block
    * It reads the id of the current bribe
    * checks to make sure there's still balance to pay out
    * calculates the claimable amount based on a daily vesting schedule
    */
    function payout() external {
        uint256 id = acceptedBribe; // read the id of the currently accepted bribe
        require (id != 0, "no bribe accepted");
        Bribe storage b = bribes[id];
        require (b.updatedAt != block.timestamp, "timestamp must not equal");
        _pay(b, cig.The_CEO(), id);
        b.updatedAt = block.timestamp;
    }

    /**
    * @dev pay calculates the payout that is vested from the bribe
    * @param _b is a bribe record ponting to storage
    * @param _ceo is the address of the current CEO
    * @param _id is the id of the bribe
    */
    function _pay(
        Bribe storage _b,
        address _ceo,
        uint256 _id
    ) internal returns (State)  {
        uint256 bal = _b.balance;
        State state = _b.state;
        if (bal > _b.claimed) {
            return state; // "all claimed"
        }
        uint256 claimable = (bal / durationLimitDays) * ((block.timestamp - _b.updatedAt) / DurationLimitSec);
        if (claimable > bal) {
            claimable = bal;
        }
        claimable = claimable - _b.claimed;
        _b.claimed += claimable;
        if (_b.target == _ceo) {
            // if the target of the bribe is the current CEO, send to them
            cig.transfer(_b.target, claimable);
            emit Paid(_id, claimable);
        } else {
            cig.transfer(address(this), claimable); // burn it!
            emit Burned(_id, claimable);
        }
        if (_b.claimed == bal) {
            acceptedBribe = 0;
            _b.state = State.PaidOut;
            emit Paidout(_id);
            return State.PaidOut;
        }
        return state;
    }

    /**
    * @dev refund collects a refund from an expired bribe. It can expire a bribe in the bribesProposed array
    * by setting the _i to less than 20 (indicating the bribe to expir)
    * @param _i the index in the bribesProposed bribe to expire (set to < 20 to ignore)
    * @param _j the index to use for the expiry slot
    */
    function refund(uint256 _i, uint256 _j, uint256 _id) external {
        Bribe storage b = bribes[_id];
        State s = b.state;
        require(s == State.Proposed || s == State.Expired, "invalid bribe state");
        if (_i < 20 && bribesProposed[_i] == _id) {
            require(_expire(_id, _i, _j, b) == State.Expired, "cannot be expired");
        } else {
            require((bribesExpired[_j] == _id), "_id not in bribesExpired"); // confirm id is in bribesExpired
        }
        _sendRefund(_id, b);
        _defunct(_id, _j, b);
    }

    function _sendRefund(uint256 _id, Bribe storage _b) internal {
        uint256 _amount = deposit[msg.sender][_id];
        if (_amount == 0) {
            return;
        }
        _b.balance -= _amount;
        deposit[msg.sender][_id] -= _amount; // record refund
        cig.transfer(msg.sender, _amount);
        emit Refunded(_id, _amount, msg.sender);
    }

    /**
    * @dev _defunct removes a bribe from bribesExpired and sets state to State.Defunct. Must be expired,
    * or balance should be 0
    * @param _id the id of the bribe
    * @param _index the position in bribesExpired
    * @param _b the bribe
    */
    function _defunct(uint256 _id, uint256 _index, Bribe storage _b) internal returns (State s) {
        s = _b.state;
        if (s != State.Expired) {
            return s;
        }
        // if the balance is 0, we can defunct early
        if (_b.balance == 0 || ((block.timestamp - _b.updatedAt) > DurationLimitSec)) {
            _b.state = State.Defunct;
            bribesExpired[_index] = 0;
            _b.updatedAt = block.timestamp;
            emit Defunct(_id);
            return State.Defunct;
        }
        return s;
    }

    function _expire (
        uint256 id,
        uint256 _i,
        uint256 _j,
        Bribe storage _b
    ) internal returns (State s) {
        if (((block.timestamp - _b.updatedAt) > DurationLimitSec) || // not updated
            (punks.punkIndexToAddress(_b.punkID) != _b.target)) {
            uint256 ex = bribesExpired[_j];
            require (ex == 0, "bribesExpired slot not empty");
            bribesExpired[_j] = id;
            bribesProposed[_i] = 0;
            _b.state = State.Expired;
            _b.updatedAt = block.timestamp;
            emit Expired(id);
            return State.Expired;
        }
        return _b.state;
    }

    /**
    * @dev getInfo returns the current state
    */
    function getInfo(address _user, uint256 _bribeID) view public returns (
        uint256[] memory,
        uint256[20] memory,
        uint256[20] memory,
        Bribe memory
    ) {
        uint[] memory ret = new uint[](11);
        Bribe memory ab;
        ret[0] = cig.balanceOf(address(this));         // balance of CIG in this contract
        ret[1] = acceptedBribe;
        if (acceptedBribe > 0) {
            ab = bribes[acceptedBribe];
        }
        if (_user != address(0)) {
            ret[2] = deposit[_user][_bribeID];  // balance of user deposit
        }

        return (ret, bribesProposed, bribesExpired, ab);

    }

}

/*
 * @dev Interface of the ERC20 standard as defined in the EIP.
 * 0xTycoon was here
 */
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface ICigtoken is IERC20 {
    function The_CEO() external view returns (address);
    function CEO_punk_index() external view returns (uint256);
    function taxBurnBlock() external view returns (uint256);
    function CEO_price() external view returns (uint256);
}

interface ICryptoPunks {
    function punkIndexToAddress(uint256 punkIndex) external returns (address);
}