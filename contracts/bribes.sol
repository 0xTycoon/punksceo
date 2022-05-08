// SPDX-License-Identifier:MIT
// Author: 0xTycoon
// Project: Cigarettes (CEO of CryptoPunks)
// Bribe punk holders to become CEOs
pragma solidity ^0.8.11;

//import "hardhat/console.sol";

/*

Creating and contributing to Bribe Proposals:
1. A new bribe, with a CIG contribution, is created for the Cryptopunk which you'd like to see become the CEO.
2. 20 bribes can exist as Proposed at one time.
3. 20 bribes can exist as Expired at one time.
4. The minimum bribe contribution amount is set to 10% of the asking price of the "CEO of Cryptopunks" title.
(This is to prevent spam, and ensure serious contributions only)
5. Anybody can increase a proposed bribe by contributing more of their CIG
6. A proposed bribe expires after 30 days of no additional contributions
7. Contributors may not withdraw their CIG from a proposed bribe, they must wait until it is expired.
8. A bribe stays in the expired list for 30 days until it is defunct.
9. Defunct bribes will be unlisted from the interface.
10. Contributors will continue to be able to withdraw their deposit from bribes in the Defunct state
11. A bribe can have a "slogan" set by the address that holds a punk specified in the Bribe

Taking Bribes:
12. A CEO must be a CEO for at least 50 blocks before taking the title
12. A CEO can take a bribe if no other bribe is active (acceptedBribeID is 0)
13. The CEO's address must own the punk specified in the bribe.
14. Once a bribe is active, it gets removed from the Proposed list,
and the CEO can call the payout function to get paid.
(But there is a twist: if the CEO loses their CEO title after accepting the bribe, any
unclaimed payment may be burned! The reason why it's burned is to discourage other CEOs from taking over)
15. Thee payment is based on a 10 day linear vesting schedule.
16. After 10 days, the active bribe may be 100% paid out. It then goes in to a PaidOut state.

Refunds:
17. CIG contributions can be refunded from bribes that have been expired or defunct.

**/

contract Bribes {

    ICigtoken immutable public cig;
    ICryptoPunks immutable public punks;
    uint256 immutable private minBlocks;
    struct Bribe {
        uint256 punkID;
        uint256 raised;   // amount of CIG raised for the bribe, can only increase
        uint256 claimed;  // amount of CIG claimed by the holder of the punk, (or burned), only after bribe taken
        State state;      // see the State enum
        uint256 updatedAt;// timestamp when state changed or amount raised increased
        bytes32 slogan;   // a message that can be set only by the punk owner
    }
    uint256 public minAmount; // minimum contribution amount

    // balance users address => (bribe id => balance)
    mapping(address => mapping(uint256 => uint256)) public deposit;

    mapping(uint256 => Bribe) public bribes;
    uint256[20] public bribesProposed;
    uint256[20] public bribesExpired;
    uint256 public bribeHeight;                 // the next Bribe ID to be assigned
    uint256 public acceptedBribeID;             // rge curently active bribe (may be 0)
    uint256 public immutable durationLimitDays; // how many days the CEO has to claim the bribe
    uint256 private immutable ClaimLimitSec;    // claimDays expressed in seconds
    uint256 private immutable StateExpirySec;   // state expiry expressed in seconds

    enum State {
        Free,     // bribe just created (in memory)
        Proposed, // bribe stored in the bribesProposed list
        Expired,  // bribe stored in the bribesExpired list
        Accepted, // bribe taken by the CEO
        PaidOut,  // bribe fully paid out (accepted -> paid out)
        Defunct   // bribe taken out of the bribesExpired list (expired -> defunct)
    }

    event New(uint256 indexed id, uint256 amount, address indexed from, uint256 punkID); // new bribe
    event Burned(uint256 indexed id, uint256 amount);                                    // bribe payment burned
    event Paid(uint256 indexed id, uint256 amount);                                      // bribe payment sent
    event Paidout(uint256 indexed id);                                                   // bribe all paidout
    event Accepted(uint256 indexed id);                                                  // bribe accepted
    event Expired(uint256 indexed id);                                                   // a bribe expired
    event Defunct(uint256 indexed id);                                                   // a bribe became defunct
    event Increased(uint256 indexed id, uint256 amount, address indexed from);           // increase a bribe
    event Refunded(uint256 indexed id, uint256 amount, address indexed to);
    event MinAmount(uint256 amount);
    event Slogan(uint256, bytes32);


    /**
    * @param _cig address of the Cigarettes contract
    * @param _punks address of the punks contract
    * @param _claimDays how many days the CEO has to claim the bribe
    * @param _stateDays how many days before proposal expires in a state
    * @param _duration, eg 86400 (seconds in a day)
    * @param _minBlocks that they must be CEO for eg 50
    */
    constructor(
        address _cig,       // 0xcb56b52316041a62b6b5d0583dce4a8ae7a3c629
        address _punks,     // eg. 0xb47e3cd837ddf8e4c57f05d70ab865de6e193bbb
        uint256 _claimDays, // eg. 10
        uint256 _stateDays, // eg. 30
        uint256 _duration,  // eg. 86400
        uint256 _minBlocks  // eg. 50
        ) {
        cig = ICigtoken(_cig);
        punks = ICryptoPunks(_punks);
        durationLimitDays = _claimDays;
        ClaimLimitSec = _duration * _claimDays;
        StateExpirySec = _duration * _stateDays;
        minBlocks = _minBlocks;
    }

    /**
    * @dev updateMinAmount updates the minimum amount required for a new bribe prorposal
    */
    function updateMinAmount() external {
        require (block.number - cig.taxBurnBlock() > minBlocks, "must be CEO for at least x block");
        minAmount = cig.CEO_price() / 10;
        emit MinAmount(minAmount);
    }

    /**
    * @dev newBribe inserts a new bribe.
    * if will first check if _j is an expired bribe, and will attempt to defunct it and clear the bribesExpired[_j] slot
    * next, if _i is less than 20, it will attempt to expire a proposal in the
    * bribesProposed[_i] slot, moving to bribesExpired[_j] which now should be clear (0). (Reverting if not clear)
    * Finally if bribesProposed[_i] then create a new proposal
    * @param _punkID the punkID to offer the bribe to
    * @param _amount the amount to offer
    * @param _i position in bribesProposed to insert new bribe. Expire any existing bribe
    * @param _j position in expiredBribes to remove and defunct. (do nothing if greater than 20)
    *
    */
    function newBribe(
        uint256 _punkID,
        uint256 _amount,
        uint256 _i,
        uint256 _j,
        bytes32 _msg
    ) external {
        require (_punkID < 10000, "invalid _punkID");
        require(_amount >= minAmount, "not enough cig");
        require(cig.transferFrom(msg.sender, address(this), _amount), "cannot send cig");
        uint256 bribeID;
        // Purge from bribesExpired, defunct _j if expired
        if (_j < 20) {
            bribeID = bribesExpired[_j];
            if (bribeID > 0) {
                // There is something in there? We must purge this bribe
                Bribe storage exb = bribes[bribeID];
                require (exb.state == State.Expired, "_j must be expired");
                require(_defunct(bribeID, _j, exb) == State.Defunct, "expected _j to defunct");
            }
            if (_i < 20) {
                // Purge from bribesProposed: if slot not empty, expire old bribe
                bribeID = bribesProposed[_i];
                if (bribeID > 0) {
                    // There is something there? We must expire
                    Bribe storage ob = bribes[bribeID];
                    require (ob.state == State.Proposed, "must be proposed");
                    require(_expire(bribeID, _i, _j, ob) == State.Expired, "cannot expire");
                }
            }
        }
        require (bribesProposed[_i] == 0, "bribesProposed at _i not empty");
        bribeID = ++bribeHeight; // starts from 1
        Bribe storage b = bribes[bribeID];
        b.punkID = _punkID;
        b.raised = _amount;
        b.slogan = _msg;
        b.state = State.Proposed;
        b.updatedAt = block.timestamp;
        bribesProposed[_i] = bribeID;
        deposit[msg.sender][bribeID] = _amount;
        emit New(bribeID, _amount, msg.sender, _punkID);
    }

    /**
    * @dev increase increase the bribe offering amount
    * @param _i the index of the bribesProposed array that stores the bribeID
    * @param _id the id of the bribe (to confirm)
    * @param _amount the amount in CIG to be added. Must be at least minAmount
    */
    function increase(uint256 _i, uint256 _id, uint256 _amount) external {
        uint256 id = bribesProposed[_i];
        require(id > 0, "no such bribe active");
        require(id == _id, "_id not found");
        require(_amount >= minAmount, "not enough cig");
        Bribe storage b = bribes[id];
        b.raised += _amount;
        b.updatedAt = block.timestamp;
        require(cig.transferFrom(msg.sender, address(this), _amount), "cannot send cig");
        deposit[msg.sender][id] += _amount; // record deposit
        emit Increased(id, _amount, msg.sender);
    }

    /**
    * @dev expire expires a bribe. The bribe is considered expired if not updated for more than DurationLimitSec
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
    * @param _i the index position of the bribe in the bribesProposed list
    * @param _id the bribe id (to confirm)
    * The bribe can be accepted if there is currently no accepted bribe.
    * The CEO must be in charge for at least 1 block, and this is checked by looking at the cig.taxBurnBlock slot

    */
    function accept(uint256 _i, uint256 _id) external {
        uint256 id = acceptedBribeID;
        address ceo = cig.The_CEO();
        if (id != 0) {
            // payout the existing bribe first
            Bribe storage ab = bribes[id];
            require(_pay(ab, ceo, id) == State.PaidOut, "acceptedBribe not PaidOut");
            // assuming that acceptedBribe will be 0 by now
        }
        require (acceptedBribeID == 0, "a bribe is currently accepted");
        id = bribesProposed[_i];
        require(id > 0, "no such bribe active");
        require(id == _id, "_id not found");
        Bribe storage b = bribes[id];
        require (ceo == msg.sender, "must be called by the CEO");
        require (cig.CEO_punk_index() == b.punkID, "punk not CEO");
        require (block.number - cig.taxBurnBlock() > minBlocks, "must be CEO for at least x block");
        bribesProposed[_i] = 0; // remove from proposed
        b.state = State.Accepted;
        acceptedBribeID = id;
        b.updatedAt = block.timestamp;
        emit Accepted(id);
    }

    /**
    * @dev setSlogan allows the punk owner to set the slogan
    * @param _id uint256 the proposal id
    * @param _slogan bytes32 the new slogan message
    */
    function setSlogan(uint256 _id, bytes32 _slogan) external {
        Bribe storage b = bribes[_id];
        require(b.state == State.Proposed, "bribe must be proposed");
        require(msg.sender == punks.punkIndexToAddress(b.punkID), "must own the punk in proposal");
        b.slogan = _slogan;
        emit Slogan(_id, _slogan);
    }

    /**
    * @dev pay sends the CIG pooled in a bribe to the current owner of the punk
    * checks to make sure it can be called once per block
    * It reads the id of the current bribe
    * checks to make sure there's still balance to pay out
    * calculates the claimable amount based on a linear vesting schedule (per second)
    */
    function payout() external {
        uint256 id = acceptedBribeID; // read the id of the currently accepted bribe
        require (id != 0, "no bribe accepted");
        Bribe storage b = bribes[id];
        require (b.updatedAt != block.timestamp, "timestamp must not equal");
        _pay(b, cig.The_CEO(), id);
        b.updatedAt = block.timestamp;
    }

    /**
    * @dev pay calculates the payout that is vested from the bribe
    * If target of the bribe is not the CEO, claim will be burned, otherwise sent to the CEO.
    * @param _b is a bribe record ponting to storage
    * @param _ceo is the address of the current CEO
    * @param _id is the id of the bribe
    */
    function _pay(
        Bribe storage _b,
        address _ceo,
        uint256 _id
    ) internal returns (State)  {
        uint256 r = _b.raised;
        State state = _b.state;
        require (state == State.Accepted, "must be accepted for payout");
        if (_b.claimed == r) {
            return state; // "all claimed"
        }
        uint256 claimable = (r / ClaimLimitSec) * (block.timestamp - _b.updatedAt);
        if (claimable > r) {
            claimable = r; // cap
        }
        if (claimable > _b.claimed) {
            claimable = claimable - _b.claimed;
        } else {
            claimable = 0;
        }
        if (claimable == 0) {
            return state;
        }
        // pay out
        _b.claimed += claimable;
        address target = punks.punkIndexToAddress(_b.punkID);
        if (target == _ceo) {
            // if the target of the bribe is the current CEO, send to them
            cig.transfer(target, claimable);
            emit Paid(_id, claimable);
        } else {
            cig.transfer(address(this), claimable); // burn it!
            emit Burned(_id, claimable);
        }
        if (_b.claimed == r) {
            acceptedBribeID = 0;
            _b.state = State.PaidOut;
            _b.updatedAt = block.timestamp;
            emit Paidout(_id);
            return State.PaidOut;
        }
        return state;
    }

    /**
    * @dev refund collects a refund from an expired bribe. It can expire a bribe in the bribesProposed array
    * by setting the _i to less than 20 (indicating the bribe to expire)
    * Bribe must be either Proposed, Expired or Defunct
    * If Proposed, it will need to be Expired before a refund can be sent.
    * @param _i the index in the bribesProposed bribe to expire (set to > 20 to ignore)
    * @param _j the index to use for the expiry slot
    */
    function refund(uint256 _i, uint256 _j, uint256 _id) external {
        Bribe storage b = bribes[_id];
        State s = b.state;
        if (_i < 20 && bribesProposed[_i] == _id) {
            require(_expire(_id, _i, _j, b) == State.Expired, "cannot be expired");
            s = State.Expired;
        }
        require(s == State.Expired || s == State.Defunct, "invalid bribe state");
        _sendRefund(_id, b);
        if (s == State.Expired) {
            _defunct(_id, _j, b); // attempt to defunct
        }
    }

    /**
    * @dev _sendRefund transfers deposited tokens back to the user whose proposal expired
    * @param _id of the bribe proposal
    * @param _b the Bribe to process
    */
    function _sendRefund(uint256 _id, Bribe storage _b) internal {
        uint256 _amount = deposit[msg.sender][_id];
        if (_amount == 0) {
            return;
        }
        _b.raised -= _amount;
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
        if (_b.raised == 0 || ((block.timestamp - _b.updatedAt) > StateExpirySec)) {
            _b.state = State.Defunct;
            bribesExpired[_index] = 0;
            _b.updatedAt = block.timestamp;
            emit Defunct(_id);
            return State.Defunct;
        }
        return s;
    }

    /**
    * @dev _expire expires a bribe from bribesProposed and moves to bribesExpired
    * @param _id the bribe ID
    * @param _i position in bribesProposed to expire
    * @param _j position in bribesExpired to place expired bribe
    */
    function _expire (
        uint256 _id,
        uint256 _i,
        uint256 _j,
        Bribe storage _b
    ) internal returns (State s) {
        if ((block.timestamp - _b.updatedAt) > StateExpirySec) {
            uint256 ex = bribesExpired[_j];
            require (ex == 0, "bribesExpired slot not empty");
            bribesExpired[_j] = _id;
            bribesProposed[_i] = 0;
            _b.state = State.Expired;
            _b.updatedAt = block.timestamp;
            emit Expired(_id);
            return State.Expired;
        }
        return _b.state;
    }

    /**
    * @dev getInfo returns the current state
    * @param _user the address to reyrn balances for
    */
    function getInfo(address _user) view public returns (
        uint256[] memory,   // ret
        uint256[20] memory, // bribesProposed
        uint256[20] memory, // bribesExpired
        Bribe memory,       // accepted acceptedBribe (if any)
        Bribe[] memory,     // array of Bribe 0-19 a proposed, 20-39 are expired
        uint256[] memory    // balances of any deposits for the _user
    ) {
        uint[] memory ret = new uint[](7);
        uint[] memory balances = new uint[](40);
        Bribe[] memory all = new Bribe[](40);
        Bribe memory ab;
        for (uint256 i = 0; i <  40; i++) {
            uint256 id;
            if (i < 20) {
                id = bribesProposed[i];
            } else {
                id = bribesExpired[i-20];
            }
            if (id > 0) {
                all[i] = bribes[id];
                if (_user != address(0)) {
                    balances[i] = deposit[_user][id];
                }
            }
        }
        ret[0] = cig.balanceOf(address(this));         // balance of CIG in this contract (tlv)
        ret[1] = acceptedBribeID;
        if (acceptedBribeID > 0) {
            ab = bribes[acceptedBribeID];
        }
        ret[2] = block.timestamp;
        ret[3] = ClaimLimitSec;                        // claim duration limit, in seconds

        if (acceptedBribeID > 0) {
            uint256 r = ab.raised;
            uint256 claimable = (r / ClaimLimitSec) * (block.timestamp - ab.updatedAt);
            if (claimable > r) {
                claimable = r; // cap
            }
            if (claimable > ab.claimed) {
                claimable = claimable - ab.claimed;
            } else {
                claimable = 0;
            }
            ret[4] = claimable;
        }
        ret[5] = minAmount;                            // minimum spend
        ret[6] = cig.allowance(_user, address(this));  // approval
        return (ret, bribesProposed, bribesExpired, ab, all, balances);
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