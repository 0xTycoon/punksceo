// SPDX-License-Identifier: MIT
// 🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔
// Author: tycoon.eth
// Project: Cig Token
// About: ERC721 for Employee ID cards
// 🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔🍔
pragma solidity ^0.8.19;

import "hardhat/console.sol";
/*

If you hold Stogies or deposited in the CIG factory, you can continue to hold
the Employee ID Card, or else it will expire.

- change so that it doesn't change pic after reclaim.
-

RULES

1. Each address can mint an NFT once. With the exceptions: (a) if their NFT
   expired, once their expired NFT gets reclaimed, then they can mint again.
   (b) The NFT gets transferred to a fresh address and the "snapshot" function
   is executed to change the picture.

2. The NFT can expire! If you do not have a minimum amount of Stogies on the
   same address, or have not deposited a minimum amount of Stogies into the
   Cigarette Factory, then anybody can call the `expire` function.

3. Expiration can be initiated by anyone at any time, if the expiration rule is
   met. If an expiry initiation transaction is successful, the token will be
   placed in the `PendingExpiry` state.

4. `PendingExpiry` state lasts 90 days. During this time, anybody can still
    put the required amount of Stogies on the address, and then call the `
    reactivate` function. This will put the NFT back into Active state.

5. Reclaiming: If the NFT has been expired in `PendingExpiry` for more than 90
    days, then it can be reclaimed by anyone, simply by calling the `reclaim`
   function. The caller must hold a minimum amount of Stogies to reclaim. Also,
   the address reclaiming must not have minted an NFT before.

6. The supply of the NFT is unlimited. However, since Stogies are required
   for minting and holding the NFT, there is an economic scarcity to the NFT.
   This means it cannot be minted forever, since CIG and ETH is needed to
   create Stogies, and both may have limited availability, if demand for any of
   these is high.

7. Each unique address can only mint a max of 1 NFT. However, they can hold
   an unlimited number of NFTs, just not mint new NFTs.

8. Reclaiming expired NFTs: Any address that hasn't minted a NFT, can
   reclaim an expired NFT. The NFT being reclaimed must be in the PendingExpiry
   state for more than 90 days. One caveat: Once an NFT is reclaimed, the
   picture will change to reflect the address that is reclaiming it. Also, the
   previous owner will be allowed to mint a new NFT again. The number if ID
   will remain the same.

9. Reactivate: NFTs that are in `PendingExpiry` state for less than 90 days
   can still be reactivated. Their owner would need to place a minimum
   amount of stogies on their address or stake them in the factory, and then
   call the reactivate method. Any address can call this method on behalf of
   any NFT id.

10. CEO can change the minimum Stogies required. 1% up or down, every 30 days.
    With the limit that the result of the change must be not higher than 0.005%
    of Stogies staked supply, and never less than 1 Stogie.

11. The punk picture is chosen randomly based on the address that minted it.
    There is also a special feature:
    Addresses starting with 5 or more zeros get a rare type. The more 0's, the
    rarer the type!

    The list is like this:

                zeros = name
                5 = Alien 3
                6 = Alienette 3
                7 = Killer Bot
                8 = Killer Botina
                9 = Green Alien
                10 = Green Alienette
                11 = Alien 4
                12 = Alienette 4
                13 = Alien 5
                14 = Alienette 5
                15 = Alien 6
                16 = Blue Ape
                17 = Alienette 6

     The more zeros, the harder it it is to get. It should be very difficult to
     get the last few, but maybe impossible to get 16 and 17.

     Some "back of the napkin" estimations if you have a GPU:

                17 = 26,722 years
                16 = 1,670 years
                15 = 104 years
                14 = 6.5 years
                13 = 0.4 years
                12 = 1.3 weeks
                11 = 14 hours
                10 = 0.9 hours

12. Changing the punk picture: It is possible to change the punk picture by
    transferring the punk to a fresh address that has never minted an ID before,
    and then calling the `snapshot` method. This method can only be called once
    per address.


END 🚬

*/

contract EmployeeIDCards {

    using DynamicBufferLib for DynamicBufferLib.DynamicBuffer;
    enum State {
        Uninitialized,
        Active,
        PendingExpiry,
        Expired
    }
    struct Card {
        address identiconSeed;   // address of identicon (the minter)
        address owner;           // address of current owner
        uint256 minStog;
        address approval;        // address approved for
        uint64 lastEventAt;      // block id of when last state changed
        uint64 index;            // sequential index in the wallet
        State state;             // NFT's state
    }

    struct Attribute {
        bool isType;
        bytes value;
    }

    mapping(bytes32 => Attribute) internal atts;    // punk-block to attribute name lookup table
    IStogie public stogie;
    ICigToken private immutable cig;                // 0xCB56b52316041A62B6b5D0583DcE4A8AE7a3C629
    IPunkIdenticons private immutable identicons;   // 0xc55C7913BE9E9748FF10a4A7af86A5Af25C46047;
    IPunkBlocks private immutable pblocks;          // 0xe91eb909203c8c8cad61f86fc44edee9023bda4d;
    IBarcode private immutable barcode;             // 0x4872BC4a6B29E8141868C3Fe0d4aeE70E9eA6735

    mapping(address => uint256) private balances;   // counts of ownership
    mapping(address => mapping(uint256 => uint256)) private ownedCards; // track enumeration
    mapping(address => uint256) public avgMinSTOG;                      // average min Stogies required
    mapping(uint256 => address) public expiredOwners;
    mapping(uint256 => Card) public cards;                              // all of the cards
    uint256 public employeeHeight;                                      // the next available employee id
    mapping(address => mapping(address => bool)) private approvalAll;   // operator approvals
    bytes4 private constant RECEIVED = 0x150b7a02;  // bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))
    mapping(address => uint64) public minters;      // ensures each card has a unique identiconSeed value, address => timestamp
    address private deployer;
    uint public minSTOG = 10 ether;                 // minimum STOG required to mint
    uint64 public minSTOGUpdatedAt;                 // block number of last change
    uint16 private immutable DURATION_MIN_CHANGE;   // 30 days, or 216000 blocks (7200 * 30)
    uint16 private immutable DURATION_STATE_CHANGE; // 90 days, or 648000 blocks (7200 * 90)
    uint64 private constant SCALE = 1e10;
    address private constant EXPIRED = 0x0000000000000000000000000000000000000E0F; // expired NFTs go here
    event StateChanged(uint256 indexed id, address indexed caller, State s0, State s1);
    event MinSTOGChanged(uint256 minSTOG, uint256 amt);
    event Snapshot(uint256 indexed id, address indexed caller);

    constructor(
        address _cig,
        uint16 _epoch,
        uint16 _duration,
        address _identicons,
        address _pblocks,
        address _barcode
    ) {
        deployer = msg.sender;
        cig = ICigToken(_cig);
        DURATION_MIN_CHANGE = _epoch;
        DURATION_STATE_CHANGE = _duration;
        identicons = IPunkIdenticons(_identicons);  // punk picking function for the punk picture
        pblocks = IPunkBlocks(_pblocks);            // stores the images of the punk traits
        barcode = IBarcode(_barcode);               // onchain barcode generator
        atts[0x9039da071f773e85254cbd0f99efa70230c4c11d63fce84323db9eca8e8ef283] = Attribute(true, "Male 1");
        atts[0xdfcbad4edd134a08c17026fc7af40e146af242a3412600cee7c0719d0ac42d53] = Attribute(true, "Male 2");
        atts[0xed94d667f893279240c415151388f335b32027819fa6a4661afaacce342f4c54] = Attribute(true, "Male 3");
        atts[0x1323f587f8837b162082b8d221e381c5e015d390305ce6be8ade3ff70e70446e] = Attribute(true, "Male 4");
        atts[0x1bb61a688fea4953cb586baa1eadb220020829a1e284be38d2ea8fb996dd7286] = Attribute(true, "Female 1");
        atts[0x47cc6a8e17679da04a479e5d29625d737670c27b21f8ccfb334e6af61bf6885a] = Attribute(true, "Female 2");
        atts[0x80547b534287b04dc7e9afb751db65a7515fde92b8c2394ae341e3ae0955d519] = Attribute(true, "Female 3");
        atts[0xc0c9e42e9d271c94b57d055fc963197e4c62d5933e371a7449ef5d59f26be00a] = Attribute(true, "Female 4");
        atts[0xf41cb73ce9ba5c1f594bcdfd56e2d14e42d2ecc23f0a4863835bdd4baacd8b72] = Attribute(true, "Zombie");
        atts[0xb1ea1507d58429e4dfa3f444cd2e584ba8909c931969bbfb5f1e21e2ac8b758d] = Attribute(true, "Ape");
        atts[0x62223f0b03d25507f52a69efbbdbcfdc7579756a7a08a95a2f0e72ada31e32b8] = Attribute(true, "Alien");
        atts[0x047228ad95cec16eb926f7cd21ac9cc9a3288d911a6c2917a24555eac7a2c0e2] = Attribute(false, "Rosy Cheeks");
        atts[0xce1f93a7afe9aad7ebb13c0add89c79d42b5e9b1272fdd1573aac99fe5d860d0] = Attribute(false, "Luxurious Beard");
        atts[0xbfac272e71cad64427175cd77d774a7884f98c7901ebc4909ada29d464c8981e] = Attribute(false, "Clown Hair Green");
        atts[0xa71068a671b554f75b7cc31ce4f8d63c377f276333d11989e77bc4a9205b5e42] = Attribute(false, "Mohawk Dark");
        atts[0x9a132de8409f80845eaec43154ff43d7bd61df75e52d96b4ded0b64626e4c88a] = Attribute(false, "Cowboy Hat");
        atts[0xfca4c5f86ef326916536dfdae74031d6960e41e10d38c624294334c3833974e2] = Attribute(false, "Mustache");
        atts[0x4483a654781ca58fa6ba3590c74c005bce612263e17c70445d6cd167e55e900b] = Attribute(false, "Clown Nose");
        atts[0x1885fe71e225eade934ab7040d533bd49efc5d66e8f2d4b5aa42477ae9892ec9] = Attribute(false, "Cigarette");
        atts[0x7411db1fe7a50d41767858710dc8b8432ac0c4fd26503ba78d2ed17789ce4f72] = Attribute(false, "Nerd Glasses");
        atts[0xdd7231e98344a83b64e1ac7a07b39d2ecc2b21128681123a9030e17a12422527] = Attribute(false, "Regular Shades");
        atts[0x24dd0364c2b2d0e6540c7deb5a0acf9177d47737a2bf41ca29b553eb69558ef9] = Attribute(false, "Knitted Cap");
        atts[0xea5efa009543229e434689349c866e4d254811928ae8a1320abb82a36d3be53f] = Attribute(false, "Shadow Beard");
        atts[0x2df03e79022dc10f7539f01da354ffe10da3ef91f1e18bc7fd096db00c381de8] = Attribute(false, "Frown");
        atts[0xf0ac7cf8c022008e16b983f22d22dae3a15b9b5abcc635bc5c20beb4d7c91800] = Attribute(false, "Cap Forward");
        atts[0x8580e735d58252637afd6fef159c826c5e7e6a5dcf1fe2d8398b3bf92c376d42] = Attribute(false, "Goat");
        atts[0x041bf83549434251cc54c0632896c8d3176b48d06150048c1bce6b6102c4e90c] = Attribute(false, "Mole");
        atts[0x591f84c8a41edd0013624b89d5e6b96cd3b0c6f1e214d4ea13a35639412f07e6] = Attribute(false, "Purple Hair");
        atts[0x54917cb8cff2411930ac1b1d36a674f855c6b16c8662806266734b5f718a9890] = Attribute(false, "Small Shades");
        atts[0x274ae610f9d7dec1e425c54ad990e7d265ba95c4f84683be4333542088ecb8e7] = Attribute(false, "Shaved Head");
        atts[0x6a400b1508bfd84ab2f4cb067d6d74dc46f74cdae7efd8b2a2d990c9f037e426] = Attribute(false, "Classic Shades");
        atts[0x3e6bc8fc06a569840c9490f8122e6b7f08a7598486649b64477b548602362516] = Attribute(false, "Vape");
        atts[0x2c382a7f1f32a6a2d0e9b0d378cb95e3dad70fe6909ff13888fe2a250bd10bb0] = Attribute(false, "Silver Chain");
        atts[0x8968ce85cb55abb5d9f6f678baeeb565638b6bad5d9be0ea2e703a34f4593566] = Attribute(false, "Smile");
        atts[0xc3075202748482832362d1b854d8274a38bf56c5ad38d418e590f46113ff10b1] = Attribute(false, "Big Shades");
        atts[0x971f7c3d5d14436a3b5ef2d658445ea527464a6409bd5f9a44f3d72e30d1eba8] = Attribute(false, "Mohawk Thin");
        atts[0x1f7b5107846b1e32944ccf8aedeaa871fc859506f51e7d12d6e9ad594a4d7619] = Attribute(false, "Beanie");
        atts[0xd35b2735e5fcc86991c8501996742b3b8c35772d92b69859de58ddd3559be46c] = Attribute(false, "Cap");
        atts[0x2004722753f61acb2cefde9b14d2c01c6bcb589d749b4ea616b4e47d83fdb056] = Attribute(false, "Clown Eyes Green");
        atts[0x05a5afe13f23e20e6cebabae910a492c91f4b862c2e1a5822914be79ab519bd8] = Attribute(false, "Normal Beard Black");
        atts[0xac5194b2986dd9939aedf83029a6e0a1d7d482eb00a5dafa05fc0aaa9b616582] = Attribute(false, "Medical Mask");
        atts[0xf94798c1aedb2dce1990e0dae94c15178ddd4229aff8031c9a5b7a77743a34d4] = Attribute(false, "Normal Beard");
        atts[0x15854f7a2b735373aa76722c01e2f289d8b18cb1a70575796be435e4ce55e57a] = Attribute(false, "VR");
        atts[0xd91f640608a7c1b2b750276d97d603512a02f4b84ca13c875a585b12a24320c2] = Attribute(false, "Eye Patch");
        atts[0x6bb15b5e619a28950bae0eb6a03f13daea1b430ef5ded0c5606b335f5b077cda] = Attribute(false, "Wild Hair");
        atts[0x7a8b4abb14bfe7b505902c23a9c4e59e5a70c7daf6e28a5f83049c13142cde5e] = Attribute(false, "Top Hat");
        atts[0x72efa89c7645580b2d0d03f51f1a2b64a425844a5cd69f1b3bb6609a4a06e47f] = Attribute(false, "Bandana");
        atts[0xfc1c0134d4441a1d7c81368f23d7dfcdeab3776687073c12af9d268e00d6c0a8] = Attribute(false, "Handlebars");
        atts[0x6ced067c29d04b367c1f3cb5e7721ad5a662f5e338ee3e10c7d64d9d109ed606] = Attribute(false, "Frumpy Hair");
        atts[0x66a6c35fd6db8b93449f29befe26e2e4bcb09799d56216ada0ef901c53cf439f] = Attribute(false, "Crazy Hair");
        atts[0x85c5daead3bc85feb0d62d1f185f82fdc2627bdbc7f1f2ffed1c721c6fcc4b4d] = Attribute(false, "Police Cap");
        atts[0x3d1f5637dfc56d4147818053fdcc0c0a35886121b7e4fc1a7cff584e4bb6414f] = Attribute(false, "Buck Teeth");
        atts[0x64b53b34ebe074820dbda2f80085c52f209d5eba6c783abdae0a19950f0787ec] = Attribute(false, "Do-rag");
        atts[0x833ca1b7f8f2ce28f7003fb78b72e259d5a484b13477ad8212edb844217225ac] = Attribute(false, "Front Beard");
        atts[0x44c2482a71c9d39dac1cf9a7daf6de80db79735c0042846cb9d47f85ccc3ba9b] = Attribute(false, "Spots");
        atts[0x4acd7797c5821ccc56add3739a55bcfd4e4cfd72b30274ec6c156b6c1d9185eb] = Attribute(false, "Big Beard");
        atts[0xc0ac7bb45040825a6d9a997dc99a6ec94027d27133145018c0561b880ecdb389] = Attribute(false, "Vampire Hair");
        atts[0xa756817780c8e400f79cdd974270d70e0cd172aa662d7cf7c9fe0b63a4a71d95] = Attribute(false, "Peak Spike");
        atts[0x71c5ce05a579f7a6bbc9fb7517851ae9394c8cb6e4fcad99245ce296b6a3c541] = Attribute(false, "Chinstrap");
        atts[0x283597377fbec1d21fb9d58af5fa0c43990b1f7c2fc6168412ceb4837d9bf86c] = Attribute(false, "Fedora");
        atts[0xbb1f372f67259011c2e9e7346c8a03a11f260853a1fe248ddd29540219788747] = Attribute(false, "Earring");
        atts[0xd5de5c20969a9e22f93842ca4d65bac0c0387225cee45a944a14f03f9221fd4a] = Attribute(false, "Horned Rim Glasses");
        atts[0xb040fea53c68833d052aa3e7c8552b04390371501b9976c938d3bd8ec66e4734] = Attribute(false, "Headband");
        atts[0x74ca947c09f7b62348c4f3c81b91973356ec81529d6220ff891012154ce517c7] = Attribute(false, "Pipe");
        atts[0x30146eda149865d57c6ae9dac707d809120563fadb039d7bca3231041bea6b2e] = Attribute(false, "Messy Hair");
        atts[0x8394d1b7af0d52a25908dc9123cc00aa0670debcac95a76c3e9a20dd6c7e7c23] = Attribute(false, "Front Beard Dark");
        atts[0xeb787e7727b2d8d912a02d9ad4c30c964b40f4cebe754bb4d3bfb09959565c91] = Attribute(false, "Hoodie");
        atts[0x6a36bcf4268827203e8a3f374b49c1ff69b62623e234e96858ff0f2d32fbf268] = Attribute(false, "Gold Chain");
        atts[0x2f237bd68c6e318a6d0aa26172032a8a73a5e0e968ad3d74ef1178e64d209b48] = Attribute(false, "Muttonchops");
        atts[0xad07511765ae4becdc5300c486c7806cd661840b0670d0f6670e8c4014de37b0] = Attribute(false, "Stringy Hair");
        atts[0x49e0947b696384a658eeca7f5746ffbdd90a5f5526f8d15e6396056b7a0dc8af] = Attribute(false, "Eye Mask");
        atts[0xc1695b389d89c71dc7afd5111f17f6540b3a28261e4d2bf5631c1484f322fc68] = Attribute(false, "3D Glasses");
        atts[0x09c36cad1064f6107d2e3bef439f87a16c8ef2e95905a827b2ce7f111dd801d7] = Attribute(false, "Clown Eyes Blue");
        atts[0xeb92e34266f6fa01c275db8379f6a521f15ab6f96297fe3266df2fe6b0e1422e] = Attribute(false, "Mohawk");
        atts[0x1892c4c9cf47baf2c613f184114519fe8208c2bebabb732405aeac1c3031dc2b] = Attribute(false, "Pilot Helmet");
        atts[0x250be814c80d8ca10bbef531b679392db8221a6fab289a6b5e637df663f48699] = Attribute(false, "Tassle Hat");
        atts[0xcd87356aa78c4fcb95e51f57578570d377440e347e0869cf1b4749d5a26340b5] = Attribute(false, "Hot Lipstick");
        atts[0x4fa682c6066fcc513a0511418aa85a0037ac59a899e9491c512b63e253697a8c] = Attribute(false, "Blue Eye Shadow");
        atts[0x36f07f03014f047728880d9f390629140a5e7c44477290695c4c1ddda356d365] = Attribute(false, "Straight Hair Dark");
        atts[0x68107f52c261820bd73e4046eb3fb5d5a1e0926611562c07054a3b89334cef34] = Attribute(false, "Choker");
        atts[0xd395cf4acda004fbc9963f85c65bf3f190c2aceb0744a535d543bc261caf6ff0] = Attribute(false, "Wild Blonde");
        atts[0xbad0fc475e9d35de67c426fc37eebb7fa38141bc2135fabd5504a911e1b05540] = Attribute(false, "Wild White Hair");
        atts[0xd10bc0475e2a0eea9f6aca91e6e82c6416f894f27fc26bb0735f29b84c54a3e6] = Attribute(false, "Tiara");
        atts[0xa0a2010e841ab7b343263c98f47a16b88656913e1353d96914f5fe492511893f] = Attribute(false, "Orange Side");
        atts[0x0e6769a10f786458ca82b57684746fe8899e35f7772543acb6a8869c4ac780cd] = Attribute(false, "Red Mohawk");
        atts[0x1004d2d00ccf8794739c7b7cbbe6048841f4c8af046b37d59e9a801a167544e2] = Attribute(false, "Purple Eye Shadow");
        atts[0x629e82a55845ea763431647fcaecfb232e275a36d8427f2568377864193801cb] = Attribute(false, "Dark Hair");
        atts[0xcd3633a5e96d615b834e90e67029f7f9f507b832e1cb263a29685b8e25f678cf] = Attribute(false, "Blonde Short");
        atts[0xe81a9c78c0ec4339dc6772f1b9bbf406b53063f8408a91fe29f63ba1c2bc7b5a] = Attribute(false, "Purple Lipstick");
        atts[0xe11278d6c191c8199a5b8bb49be7f806b837a9811195c903d844a74c4c4a704e] = Attribute(false, "Pigtails");
        atts[0x411ec1566affa22bd67b13a7c49ac060c018e1c806cd314cd2186118dd55e129] = Attribute(false, "Straight Hair Blonde");
        atts[0x1868a04ecae06e10c5b6dcbbed4befac1ed03dda2cf86ddbd855466cc588809f] = Attribute(false, "Welding Goggles");
        atts[0x3511b04ac6a3d46305172269904dc469a40f380a4e7afa8742ce6e6a44825c4a] = Attribute(false, "Pink With Hat");
        atts[0x2857e47dcac3b744dd7d41617ce362f1dd3ae8eb836685cc18338714205b036c] = Attribute(false, "Blonde Bob");
        atts[0x2e9a5434da70e5ea2ed439b3a33aac60bd252c92698c1ba37e9ed77f975c6cab] = Attribute(false, "Green Eye Shadow");
        atts[0x8c0e60b85ff0f8be1a87b28ae066a63dcc3c02589a213b0856321a73882515f9] = Attribute(false, "Straight Hair");
        atts[0xe651be5dd43261e6e9c1098ec114ab5c44e7cb07377dc674336f1b3d34428fe4] = Attribute(false, "Half Shaved");
        atts[0x1cd064e6db4e7c5180ccf5f2afe1370c6539b525fe3bea9c358f24a7cbdb50ad] = Attribute(false, "Black Lipstick");
        atts[0x398534927262d4f6993396751323ddd3e8326784a8e9a4808f17b99e6693835e] = Attribute(false, "Stogie");
        atts[0x3b4d5e3dd66b09dd19cc19643986e2dc15e70251b31a4e5a463ecd996f7c3dc7] = Attribute(false, "Earphone");
        atts[0x550aa6da33a6eca427f83a70c2510cbc3c8bdb8a1ce5e5c3a32b2262f97c4aa1] = Attribute(false, "Employee Cap");
        atts[0xe2f3dcf809c00413a95bf007b46163923170ba8a0fbdaba7380f5c5079fcc98c] = Attribute(false, "Headphones");
        atts[0x975e45b489dc6726c2a27eb784068ec791a22cf46fb780ced5e6b2083f32ebc3] = Attribute(false, "Headphones Red");
        atts[0x421c9c08478a3dfb8a098fbef56342e7e0b53239aaa40dd2d56951cc6c178d35] = Attribute(false, "Headphones Yellow");
        atts[0xaffb8a29fc5ed315e2a1103abc528d4f689c8365b54b17538f96e6bcae365633] = Attribute(false, "Gas Mask");
        atts[0x314ff09b8866e566e22c7bf1fe4227185bc37e1167a84aaf299f5e016ca2ea7b] = Attribute(false, "Goggles");
        atts[0xe5fd4286f4fc4347131889d24238df4b5ba8d8d4985cbd9cb30d447ec14cbb2f] = Attribute(false, "Pen");
        atts[0xaeae7be74009ff61e63109240ea8e00b3bd6d166bf8a7f6584f64ff75e783f09] = Attribute(false, "Pencil");
        atts[0x1cc630fd6d4fff8ca66aacb5acdba26a0a14ce5fd8f9cb60b002a153d1582b4e] = Attribute(false, "Red Hat");
        atts[0xbbb91da98e74857ed34286d7efaf04751ac3f4d7081d62a0aa3b09278b5ee55a] = Attribute(false, "Yellow Hat");
        atts[0x3fbda43b0bda236b4f6f6dba8b7052381641b3d92ce4b49b4a2e9be390980019] = Attribute(false, "White Hat");
        atts[0x10214dd24c8822f95b3061229664e567e7da89d1f8a408179e12bf38be2c1430] = Attribute(false, "Suit");
        atts[0xb52fd5c8112bb81b2c05dd854ac28867bf72fd52124cb27aee3de68a19c87812] = Attribute(false, "Suit Black");
        atts[0xd7a861eff7c9242c2fc79148cdb44128460adae80afe1ba79c2d1eae290fb883] = Attribute(true, "Bot");
        atts[0x7d3615eb6acf9ca19e31084888916f38df240bce4009857da690e4681bf8d4b0] = Attribute(true, "Botina");
        atts[0x18a26173165d296055f2dfd8a12afc0a3e85434dd9d3f9c3ddd1eabc37ff56bc] = Attribute(true, "Killer Bot");
        atts[0xb93c33f3b6e2e6aef9bd03b9ed7a064ed00f8306c06dfc93c76ae30db7a3f2b4] = Attribute(true, "Killer Botina");
        atts[0x9242f3766d6363a612c9e88734e9c5667f4c82e07d00b794481f5b41b97047e8] = Attribute(true, "Green Alien");
        atts[0x0c924a70f72135432a52769f20962602647a5b6528675c14bb318eaf4cbb2753] = Attribute(true, "Green Alienette");
        atts[0xcd6f6379578617fc2da9c1d778e731bebaa21e9be1ed7265963ec43076d17a10] = Attribute(true, "Blue Ape");
        atts[0x53f8bd0b36b2d3d9abc80e02d6fe9ed6a07068216cd737604c0c36ac60f458dc] = Attribute(true, "Alien 2");
        atts[0xeca5ecd41019c8240974e9473044bf1a01598e7c650939425f53f561e959ec46] = Attribute(true, "Alien 3");
        atts[0x061c5772160bfea6296a0317f6eff655398285ab18dbe89497436563445eeddc] = Attribute(true, "Alien 4");
        atts[0x224b0f8059a7c50a19036c71e7500fd115adfd3af915c8d6d6639248c6e41283] = Attribute(true, "Alien 5");
        atts[0xfb3556140e6f92df2d04796b8d8c5f6732abf43c07eb7034a90672cd4f9af372] = Attribute(true, "Alien 6");
        atts[0xe9986a150e097f2cadc995279f34846ae9786b8ce35070b152f819d7a18d7760] = Attribute(true, "Alienette 2");
        atts[0x0a215113c1e36c8cf69812b89dd912e3e2f1d70ab8c7691e0439a002d772f56d] = Attribute(true, "Alienette 3");
        atts[0xac4fc861f4029388de1fa709cb865f504fb3198a6bf4dad71ff705a436c406c2] = Attribute(true, "Alienette 4");
        atts[0xbefcd0e4ecf58c1d5e2a435bef572fca90d5fcedf6e2e3c1eb2f12b664d555a4] = Attribute(true, "Alienette 5");
        atts[0x54526cc56c302d9d091979753406975ad06ca6a58c7bea1395ae25350268ab36] = Attribute(true, "Alienette 6");
        atts[0xffa2b3215eb937dd3ebe2fc73a7dd3baa1f18b9906d0f69acb3ae76b99130ff7] = Attribute(true, "Pink Ape");
        atts[0x46151bb75270ac0d6c45f21c75823f7da7a0c0281ddede44d207e1242e0a83f6] = Attribute(true, "Male 5");
        atts[0xef8998f2252b6977b3cc239953db2f5fbcd066a5d454652f5107c59239265884] = Attribute(true, "Male 6");
        atts[0x606da1a8306113f266975d1d05f6deed98d3b6bf84674cc69c7b1963cdc3ea86] = Attribute(true, "Male 7");
        atts[0x804b2e3828825fc709d6d2db6078f393eafdcdedceae3bdb9b36e3c81630dd5e] = Attribute(true, "Apette"); // missing
        atts[0x54354de4503fcf83c4214caefd1d4814c0eaf0ce462d1783be54ff9f952ec542] = Attribute(true, "Female 5");
        atts[0x8a643536421eae5a22ba595625c8ba151b3cc48f2a4f86f9671f5c186b027ceb] = Attribute(true, "Female 6");
        atts[0x4426d573f2858ebb8043f7fa39e34d1441d9b4fa4a8a8aa2c0ec0c78e755df0e] = Attribute(true, "Female 7");
        atts[0x1908d72c46a0440b2cc449de243a20ac8ab3ab9a11c096f9c5abcb6de42c99e7] = Attribute(true, "Alientina");
        atts[0xcedf32c147815fdc0d5f7e785f41a33dfc773e45bbd1a9a3b5d86c264e1b8ac5] = Attribute(true, "Zombina");
    }

    /**
    * getStats gets the information about the current user
    */
    function getStats(address _holder) view external returns(uint256[] memory, uint256[] memory, uint256[] memory) {
        uint[] memory ret = new uint[](23);
        uint[] memory inventory = new uint[](20);
        uint[] memory expired = new uint[](40);
        ret[0] = minSTOG;
        ret[1] = minters[_holder];
        ret[2] = avgMinSTOG[_holder];
        ret[3] = balanceOf(_holder);
        ret[4] = balanceOf(EXPIRED);
        for (uint i = 0; i < 20; i++) {
            inventory[i] = tokenOfOwnerByIndex(_holder, i);
        }
        for (uint i = 0; i < 40; i++) {
            expired[i] = tokenOfOwnerByIndex(_holder, i);
        }
        return (ret, inventory, expired);
    }

    /**
    * @dev setStogie can only be called once
    */
    function setStogie(address _s) public {
        require(msg.sender == deployer, "not deployer");
        require(address(stogie) == address(0), "stogie already set");
        stogie = IStogie(_s);
    }

    /**
    * @dev issueID mints a new ID card. The account must be an active stogie
    *   staker would be called from the Stogies contract. Stogies would ensure
    *   not called form a contract
    */
    function issueID(address _to) external {
        uint256 min = minSTOG;
        uint256 id = _issueID(_to, min);
        IStogie.UserInfo memory i = stogie.farmers(_to);
        (uint256 newAvg, uint256 newBal) = _transfer(address(0), _to, id, min);
        require(
            i.deposit >= newAvg * newBal, "need to stake more STOG");
    }

    /**
    * @dev issueID mints a new NFT. Caller needs to be holding enough STOG
    */
    function issueID() external {
        uint256 min = minSTOG;
        uint256 id = _issueID(msg.sender, min);
        IStogie.UserInfo memory i = stogie.farmers(msg.sender);
        (uint256 newAvg, uint256 newBal) = _transfer(address(0), msg.sender, id, min);
        require(
            i.deposit >= newAvg * newBal, "need to stake more STOG");
    }

    function _issueID(address _to, uint256 min) internal returns(uint256 id) {
        require(minters[_to] == 0, "_to has already minted this pic");
        id = employeeHeight;
        Card storage c = cards[id];
        c.owner = _to;
        c.state = State.Active;
        c.lastEventAt = uint64(block.number);
        c.minStog = min;                    // record the minSTOG
        c.identiconSeed = _to;                  // save seed, used for the identicon
        emit StateChanged(
            id,
            msg.sender,
            State.Uninitialized,
            State.Active
        );
        unchecked {employeeHeight = id++;}
        minters[_to] = uint64(block.timestamp); // mark address as a minter
    }

    /**
    * @dev expire a token.
    *   Initiate s.PendingExpiry if account does not possess minimal stake.
    *   Transfers the NFT to EXPIRED account.
    * @param _tokenId the token to expire
    */
    function expire(uint256 _tokenId) external returns (State) {
        Card storage c = cards[_tokenId];
        State s = c.state;
        require(s == State.Active, "invalid state");
        address o = c.owner;
        uint256 bal = balanceOf(o);
        IStogie.UserInfo memory i = stogie.farmers(o);
        uint256 min = avgMinSTOG[c.owner] * bal; // assuming owner has at least 1
        require (i.deposit < min, "rule not satisfied");  // deposit below the min?
        c.state = State.PendingExpiry;
        c.lastEventAt = uint64(block.number);
        emit StateChanged(
            _tokenId,
            msg.sender,
            s,
            State.PendingExpiry
        );
        expiredOwners[_tokenId] = o;
        _transfer(c.owner, EXPIRED, _tokenId, c.minStog);
        return State.PendingExpiry;
    }

    /**
    * @dev reactivate a token. Must be in State.PendingExpiry state.
    *    At least a minimum of Stogies are needed to reactivate.
    *    Can be called by expired owner.
    */
    function reactivate(uint256 _tokenId) external returns (State) {
        Card storage c = cards[_tokenId];
        State s = c.state;
        require(s == State.PendingExpiry, "invalid state");
        address o = expiredOwners[_tokenId];
        require(o == msg.sender, "not your token");
        require(
            c.lastEventAt > block.number - DURATION_STATE_CHANGE,
            "time is up");                                     // expiration must be under the deadline
        (uint256 newAvg, uint256 newBal) = _transfer(EXPIRED, o, _tokenId, minSTOG); // return token to owner
        IStogie.UserInfo memory i = stogie.farmers(o);
        require(
            i.deposit >= newAvg * newBal, "insert more STOG"); // must have Stogies or staking Stogies
        c.state = State.Active;
        c.lastEventAt = uint64(block.number);
        emit StateChanged(
            _tokenId,
            msg.sender,
            State.PendingExpiry,
            State.Active
        );
        expiredOwners[_tokenId] = address(0);
        c.minStog = minSTOG;                                    // reset to current value
        return State.Active;
    }



    /**
    * @dev respawn an expired token. Can only be respawned by an address that
    *    hasn't minted. This is because respawn changes the badge picture.
    *    in other words, the c.identiconSeed is updated. The minimum Stogies
    *    value of the NFT will be reset to the current minSTOG value.
    * @param _tokenId the token id to respawn
    */
    function reclaim(uint256 _tokenId) external {
        require(minters[msg.sender] == 0,
            "_to has minted a card already");                  // cannot mint more than one
        Card storage c = cards[_tokenId];
        require(c.state == State.PendingExpiry, "must be PendingExpiry");
        require(
            c.lastEventAt < block.number - DURATION_STATE_CHANGE,
            "time is not up");                                  // must be over the deadline
        c.minStog = minSTOG;                                    // reset minStog
        (uint256 newAvg, uint256 newBal) = _transfer(address(this), msg.sender, _tokenId, minSTOG);
        IStogie.UserInfo memory i = stogie.farmers(msg.sender); // check caller's deposit
        require(
            i.deposit >= newAvg * newBal,
            "insert more STOG");                                // caller  must have Stogies or staking Stogies
        emit StateChanged(
            _tokenId,
            msg.sender,
            State.PendingExpiry,
            State.Expired
        );
        emit StateChanged(
            _tokenId,
            msg.sender,
            State.Expired,
            State.Active
        );

        c.state = State.Active;
        c.identiconSeed = msg.sender;                       // change the identicon to reclaiming address
        minters[c.identiconSeed] = 0;                       // allow original owner to mint again
        minters[msg.sender] = uint64(block.timestamp);
        c.lastEventAt = uint64(block.number);
    }

    /**
    * @notice allows the holder of the NFT to change the identiconSeed used to
    *    generate the picture on the id card. Holder must not be on the minters
    *    list. Can only be called once per address. See the rules for more details.
    *
    * @param _tokenId the token id to change the picture for
    */
    function snapshot(uint256 _tokenId) external {
        Card storage c = cards[_tokenId];
        require(c.state == State.Active, "state must be Active");
        require(c.owner == msg.sender, "you must be the owner");
        require(
            minters[msg.sender] == 0,
            "id with this pic already minted"); // must be a fresh address
        minters[c.identiconSeed] = 0;           // allow original minter user to mint again
        c.identiconSeed = msg.sender;           // change to a new picture, destroying the old
        minters[msg.sender] = uint64(block.number);
        emit Snapshot(_tokenId, msg.sender);
    }



    /**
    * minSTOGChange allows the CEO of CryptoPunks to change the minSTOG
    *    either increasing or decreasing by %2.5. Cannot be below 1 STOG, or
    *    above 0.005% of staked SLP supply.
    * @param _up increase by 1% if true, decrease otherwise.
    */
    function minSTOGChange(bool _up) external {unchecked {
            require(msg.sender == cig.The_CEO(), "need to be CEO");
            require(block.number > cig.taxBurnBlock() - 20, "need to be CEO longer");
            require(block.number > minSTOGUpdatedAt + DURATION_MIN_CHANGE, "wait more blocks");
            minSTOGUpdatedAt = uint64(block.number);
            uint256 amt = minSTOG / 10000 * 250;                        // %2.5
            uint256 newMin;
            if (_up) {
                newMin = minSTOG + amt;
                require(newMin <= cig.stakedlpSupply() / 100000 * 5, "too big");// must be less than 0.005% of staked supply
            } else {
                newMin = minSTOG - amt;
                require(newMin > 1 ether, "min too small");
            }
            minSTOG = newMin;                                         // write
            emit MinSTOGChanged(minSTOG, amt);
        }}

    /**
    * @dev called after an erc721 token transfer, after the counts have been updated
    */
    function addEnumeration(address _to, uint256 _tokenId) internal {
        uint256 last = balances[_to] - 1; // the index of the last position
        ownedCards[_to][last] = _tokenId; // add a new entry
        cards[_tokenId].index = uint64(last);
    }

    function removeEnumeration(address _from, uint256 _tokenId) internal {
        uint256 height = balances[_from];  // last index
        uint256 i = cards[_tokenId].index; // index
        if (i != height) {
            // If not last, move the last token to the slot of the token to be deleted
            uint256 lastTokenId = ownedCards[_from][height];
            ownedCards[_from][i] = lastTokenId;   // move the last token to the slot of the to-delete token
            cards[lastTokenId].index = uint64(i); // update the moved token's index
        }
        cards[_tokenId].index = 0;                // delete from index
        delete ownedCards[_from][height];         // delete last slot
    }

    /***
    * ERC721 functionality.
    */

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /// @notice Count NFTs tracked by this contract
    /// @return A count of valid NFTs tracked by this contract, where each one of
    ///  them has an assigned and queryable owner not equal to the zero address
    function totalSupply() external view returns (uint256) {
        return employeeHeight;
    }

    /// @notice Enumerate valid NFTs
    /// @dev Throws if `_index` >= `employeeHeight`.
    /// @param _index A counter less than `employeeHeight`
    /// @return The token identifier for the `_index`th NFT,
    ///  (sort order not specified)
    function tokenByIndex(uint256 _index) external view returns (uint256) {
        require(_index >= employeeHeight, "index out of range");
        return _index; // index starts from 0
    }

    /// @notice Enumerate NFTs assigned to an owner
    /// @dev Throws if `_index` >= `balanceOf(_owner)` or if
    ///  `_owner` is the zero address, representing invalid NFTs.
    /// @param _owner An address where we are interested in NFTs owned by them
    /// @param _index A counter less than `balanceOf(_owner)`
    /// @return The token identifier for the `_index`th NFT assigned to `_owner`,
    ///   (sort order not specified)
    function tokenOfOwnerByIndex(address _owner, uint256 _index) public view returns (uint256) {
        require(_index <= balances[_owner], "index out of range");
        require(_owner != address(0), "invalid _owner");
        return ownedCards[_owner][_index];
    }

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address _holder) public view returns (uint256) {
        // each address can only own 1
        require(_holder != address(0), "invalid _owner");
        return balances[_holder];
    }

    function name() public pure returns (string memory) {
        return "Cigarette Factory ID Cards";
    }

    function symbol() public pure returns (string memory) {
        return "EMPLOYEE";
    }

    bytes constant badgeStart = '<svg xmlns="http://www.w3.org/2000/svg" width="600" height="500" shape-rendering="crispEdges"><defs><style>.g2,.g4,.g5{stroke:#000;fill:#a8a9a8;stroke-width:0}.g4,.g5{fill:#dcdddc}.g5{fill:#696a69}.g7{fill:#dedede}.g9{fill:#a0a0a0}.g10{fill:#7c7b7e}.w{fill:#fff}.boxb{fill:#38535e}</style></defs><path d="M30 100h230v10H30zM20 110h10v10H20zM10 120h10v360H10zM20 480h10v10H20zM30 490h540v10H30zM570 480h10v10h-10zM580 120h10v360h-10zM570 110h10v10h-10zM340 100h230v10H340z"/><path d="M320 120h260v340H320z" style="fill:#ebebeb"/><path d="M20 130h300v340H20zM20 120h550v10H20z" class="g7"/><path d="M20 120h10v10H20zM20 460h10v10H20zM30 110h540v10H30zM570 120h10v10h-10z" class="w"/><path d="M570 130h10v10h-10zM570 450h10v10h-10z" class="g7"/><path d="M570 460h10v10h-10z" class="w"/><path d="M320 460h250v10H320z" class="g4"/><path d="M30 470h540v10H30z" class="w"/><path d="M30 480h540v10H30zM20 470h10v10H20zM570 470h10v10h-10z" class="g9"/><path d="M330 0h10v130h-10z"/><path d="M260 0h80v10h-80zM260 120h80v10h-80z"/><path d="M260 0h10v130h-10z"/><path d="M270 10h20v60h-20z" class="g2"/><path d="M290 10h40v60h-40z" style="stroke:#000;fill:#ccc;stroke-width:0"/><path d="M270 70h60v20h-60z" class="g4"/><path d="M290 50h20v10h-20zM290 70h20v10h-20zM280 60h10v10h-10zM310 60h10v10h-10zM280 90h40v10h-40z"/><path d="M280 70h10v10h-10zM310 70h10v10h-10zM320 60h10v10h-10z" class="g2"/><path d="M270 80h10v10h-10zM320 80h10v10h-10z"/><path d="M270 100h60v20h-60z" style="stroke:#000;fill:#7a7a7a;stroke-width:0"/><path d="M280 100h40v10h-40zM270 90h10v10h-10zM320 90h10v10h-10z" class="g5"/><path d="M260 130h80v10h-80z" style="fill:#bebfbe;stroke-width:0"/><path d="M40 160h240v250H40z" style="stroke:#38535e;fill:#598495;stroke-width:0;stroke-alignment:inner"/><path d="M40 160h240v10H40z" class="boxb"/><path d="M40 160h10v250H40z" class="boxb"/><path d="M40 400h240v10H40z" class="boxb"/><path d="M270 160h10v250h-10z" class="boxb"/><path d="M310 380h240v20H310zM310 340h60v20h-60zM380 340h60v20h-60zM450 340h30v20h-30zM490 340h20v20h-20zM520 340h30v20h-30z" class="g10"/>';

    bytes constant badgeText = '<svg><defs><style>@font-face {font-family: "C64";src: url(data:font/woff2;base64,d09GMgABAAAAAAVgAA0AAAAAFlgAAAUJAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP0ZGVE0cGhgGYACCWhEICpsEkngLgRwAATYCJAOBbgQgBYQZB4NcG8oQIxGmjE4A4K+TJ0Osoz0yHHiUIkeu8JnCS5uIH1YhT02PLEKlTJ7cqgZVF/5IPHyugb2f7G5SAkXAGljj+Hr2gK6WSeiyg3PnT0iMUWvb91CYfvgbZppEPEaGUigFhE0YA/WRi3POTSggSRRs2fnJ2yeodbZZS3aT5NqzSb5BVxKj6QrdHMN9vERqLCweg+Eon8X6+uo2ar9f/XKLyXSxG1KhEc0iIT+B+6KChSLq0RKhkhiaSi2eIqURK5lMKJlF3GQEMrhGtO1N/74I+LMvU4FPHryBP75yAIXRGA8SOiTkMiVu6qk6hE6HTsjqyBRDN6RUIxAAcGSFcSOOGBYNRZgFcRm9ArNQyMiYhgJHMQLTsDaBqkqYK2DYGmaxS7RG+9l+oAIy6IiBAERCAgAEmQ4A+qH8VNQgwLhXk+wdpp+fVqc3GE1mEeRfRojWAPsAd7Ee0kfyaYhVENsAkGjkSLKQBEUiwcczH8tj/BlZjPR4gciOhukMmG/KPkMmmc0uuWmX7vPFjZQCTKpgN+4z58WghjLNctLuw6qV7mzQFaQCKPjwbOxyRrRqww5jG54lgTpsLi3QH/iqrBWMoFWcTDY6QmOfrVTozOCl7F1evHrv9iAMzShgDTA/KkFTbR4xVisj1YDKNcsYXonRTZiFGJc9rPsYza7KqMo4bBzqMTNDzNQ1l47OjQ3lXd26BA7vUdPRU4hvGaPT8ywb8swsskD+EsahHh1dPpzz9uUMix8UdUNi2YAfuxDlzC5gWqqmqWsjrK2laIRALSvnilvXRppxJ1ePi1aV47jqbJ9eQbiH7Sbfs48oewX3cKofdLojr+rLGjEyjpQIm+VOY/cJG3eK5DX7sJzeFFVHRuvep641aKXl+UL1ma56eRh9ldT9GDGyPCdL85UU+LA+qiN/zrHa2uGPJ/TIKHqeop5Ha3NLFHFspGdLghd6AgUoRpTdTSHLT9TqwVwc6y3IIatqwjAogOmjn+dVGgrzNfQLN34S35USopfAxoYuaOwykhOkB/bkWAKk6ZxgRWuw1nh5KkHiENHImzSY6+xKj3sC9taEpeknfdBVklDE0Id1GE8pKXVxSjU70sggixzyKKCIEsqgIUGGAhUWWGFLs/+lOf7hhAtueOCFD34EEEQIYUQQRQxxeeK4k+TuSfDjjeRcRgoqARYybCjfYTh8p25MpS0FFKifGgFi/c9/+De//W3YHHrPm8V/gagSCIqGEaASAIAlFVCFihEovLkrylL0tWavtplBK5dEecQJAvsQDJQEPCwkjPVSABZp6jQUV6QJ92g22Z92ir9pb2psuXgwxBmM6EbgIOg0jHVOmnCHZot8aWesv2hvQ6SHDEbHcR+zONk52Fnw5gEqouXmbWfOihCt3GjBSZDNcI041cvN6uhiSYIn3xCptvwCJPFfW9GJn3gTPyQ0b5DPWEQWF9ibnk3Ug0fY62T/XvjFcNjc0t3O2AV+pe2oOU8P6pq7uFo7OiAcrJwc1XRbPuF9MLQ6HS3H99AeknDy8qjeoYVnZdgqzUADbejzGxb0fHZFF+g3HMXT9PSmrAx+wX0gIskGk2hcqtQarU5vMJrMFqvN7nC63B4vgAgTyrAcL4iSHCCk0nTDtGzH9XyECWUcL4iSrKiabpiW7bhe/bf/7yORMBGixBBLXKovbQhnIAgMgcLAwhGfTgAEgSFQGFg44tMZgCAwBAoDq3Y=);}.t {fill: #ff04b4; stroke: none; font-size: 26px; font-family: \'C64\',monospace; text-anchor: end}</style></defs><text x="550px" y="190px" class="t">CIG FACTORY</text><text x="550px" y="232px" class="t">EMPLOYEE</text><text x="550px" y="274px" class="t">#';
    bytes constant badgeEnd = '</text><text x="550px" y="320px" style="font-family: \'C64\',monospace; text-anchor: end; font-size: 16.5px; fill: #a7a7a7;">CONFIDIMUS IN CEO</text></svg></svg>';

    function _generateBadge(uint256 _tokenId, address _seed) internal view
    returns (bytes memory, bytes32[] memory traits) {
        DynamicBufferLib.DynamicBuffer memory result;
        string memory bars = barcode.draw(_tokenId, "40", "408", "ebebeb", 52, 6);
        traits = identicons.pick(_seed, 0);
        string memory punk = pblocks.svgFromKeys(traits, 40, 160, 240, 0);
        result.append(badgeStart, bytes(bars), bytes(punk));
        result.append(badgeText, bytes(_intToString(_tokenId)), badgeEnd);
        return (result.data, traits);
    }

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 _tokenId) public view returns (string memory) {
        DynamicBufferLib.DynamicBuffer memory result;
        require(_tokenId < employeeHeight, "index out of range");
        Card storage c = cards[_tokenId];
        (bytes memory badge, bytes32[] memory traits) = _generateBadge(_tokenId, c.identiconSeed);
        result.append('{\n"description": "Employee ID Cards for the Cigarette Factory",', "\n",
            '"external_url": "https://cigtoken.eth.limo/#idCard-');
        result.append(bytes(_intToString(_tokenId)), '",', "\n");
        result.append('"image": "data:image/svg+xml;base64,');
        result.append(bytes(Base64.encode(badge)), '",', "\n");
        result.append('"attributes": [ ', _getAttributes(traits), "]\n}");
        return string(abi.encodePacked("data:application/json;base64,",
            Base64.encode(
                result.data
            )
        ));
    }

    function _getAttributes(bytes32[] memory traits) internal view returns (bytes memory) {
        DynamicBufferLib.DynamicBuffer memory result;
        bytes memory comma = "";
        for (uint256 i = 0; i < traits.length; i++) {
            if (comma.length > 0) {
                result.append(comma);
            } else {
                comma = ",\n";
            }
            Attribute memory a = atts[traits[i]];
            if (a.isType) {
                result.append('{"trait_type": "Type", "value": "', a.value, '"}');
            } else {
                result.append('{"trait_type": "Accessory", "value": "', a.value, '"}');

            }
        }
        return result.data;
    }

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 _tokenId) public view returns (address) {
        require(_tokenId >= employeeHeight, "index out of range");
        Card storage c = cards[_tokenId];
        address owner = c.owner;
        require(owner != address(0), "not minted.");
        return owner;
    }

    /**
    * @dev Throws unless `msg.sender` is the current owner, an authorized
    *  operator, or the approved address for this NFT. Throws if `_from` is
    *  not the current owner. Throws if `_to` is the zero address. Throws if
    *  `_tokenId` is not a valid NFT.
    * @param _from The current owner of the NFT
    * @param _to The new owner
    * @param _tokenId The NFT to transfer
    */
    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes memory _data) external {
        _transfer(_from, _to, _tokenId, cards[_tokenId].minStog);
        require(_checkOnERC721Received(_from, _to, _tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    /**
    * @dev Throws unless `msg.sender` is the current owner, an authorized
    *  operator, or the approved address for this NFT. Throws if `_from` is
    *  not the current owner. Throws if `_to` is the zero address. Throws if
    *  `_tokenId` is not a valid NFT.
    * @param _from The current owner of the NFT
    * @param _to The new owner
    * @param _tokenId The NFT to transfer
    */
    function safeTransferFrom(address _from, address _to, uint256 _tokenId) external {
        bytes memory data = new bytes(0);
        _transfer(_from, _to, _tokenId, cards[_tokenId].minStog);
        require(_checkOnERC721Received(_from, _to, _tokenId, data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    function transferFrom(address _from, address _to, uint256 _tokenId) external {
        _transfer(_from, _to, _tokenId, cards[_tokenId].minStog);
    }

    function _transfer(
        address _from,
        address _to,
        uint256 _tokenId,
        uint256 _min) internal
        returns (uint256 toAvg, uint256 toBal) {
        address a;
        if (_from != address(0)) {
            require(_tokenId < employeeHeight, "index out of range");
            require(_from != _to, "cannot send to self");
            require(_to != address(0), "_to is zero");
            require(cards[_tokenId].state == State.Active, "state must be Active");
            address o = cards[_tokenId].owner;                  // assuming o can never be address(0)
            require(o == _from, "_from must be owner");         // also ensures that the card exists
            a = cards[_tokenId].approval;
            require(
                msg.sender == address(stogie) ||                // is executed by the Stogies contract
                o == address(this) ||                           // or is executed by this contract
                o == msg.sender ||                              // or executed by owner
                a == msg.sender ||                              // or owner approved the sender
                (approvalAll[o][msg.sender]), "not permitted"); // or owner approved the operator, who's the sender
            uint fromBal = balances[_from]--;
            balances[_from] = fromBal;
            if (fromBal == 0) {
                avgMinSTOG[_from] = 0;
            } else {
                avgMinSTOG[_from] = (avgMinSTOG[_from] - _min) * SCALE / fromBal;
            }
            removeEnumeration(_from, _tokenId);
        }
        toBal = balances[_to]++;
        balances[_to] = toBal;
        if (toBal == 1) {
            toAvg = _min;
        } else {
            toAvg = (avgMinSTOG[_to] + _min) * SCALE / toBal;
        }
        avgMinSTOG[_to] = toAvg;
        cards[_tokenId].owner = _to;                            // set new owner
        addEnumeration(_to, _tokenId);
        emit Transfer(_from, _to, _tokenId);
        if (a != address(0)) {
            cards[_tokenId].approval = address(0);              // clear previous approval
            emit Approval(msg.sender, address(0), _tokenId);
        }
    }

    /**
    * @dev approve can be set by the owner or operator
    * @param _to The new approved NFT controller
    * @param _tokenId The NFT to approve
    */
    function approve(address _to, uint256 _tokenId) external {
        require(_tokenId < employeeHeight, "index out of range");
        address o = cards[_tokenId].owner;
        require(o == msg.sender || isApprovedForAll(o, msg.sender), "action on token not permitted");
        cards[_tokenId].approval = _to;
        emit Approval(msg.sender, _to, _tokenId);
    }
    /**
    * @dev approve can be set by the owner or operator
    * @param _operator Address to add to the set of authorized operators
    * @param _approved True if the operator is approved, false to revoke approval
    */
    function setApprovalForAll(address _operator, bool _approved) external {
        approvalAll[msg.sender][_operator] = _approved;
        emit ApprovalForAll(msg.sender, _operator, _approved);
    }

    /**
    * @notice Get the approved address for a single NFT
    * @dev Throws if `_tokenId` is not a valid NFT.
    * @param _tokenId The NFT to find the approved address for
    * @return Will always return address(this)
    */
    function getApproved(uint256 _tokenId) public view returns (address) {
        return cards[_tokenId].approval;
    }

    /**
    * @param _owner The address that owns the NFTs
    * @param _operator The address that acts on behalf of the owner
    * @return Will always return false
    */
    function isApprovedForAll(address _owner, address _operator) public view returns (bool) {
        return approvalAll[_owner][_operator];
    }

    /**
    * @notice Query if a contract implements an interface
    * @param interfaceId The interface identifier, as specified in ERC-165
    * @dev Interface identification is specified in ERC-165. This function
    *  uses less than 30,000 gas.
    * @return `true` if the contract implements `interfaceID` and
    *  `interfaceID` is not 0xffffffff, `false` otherwise
    */
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return
        interfaceId == type(IERC721).interfaceId ||
        interfaceId == type(IERC721Metadata).interfaceId ||
        interfaceId == type(IERC165).interfaceId ||
        interfaceId == type(IERC721Enumerable).interfaceId ||
        interfaceId == type(IERC721TokenReceiver).interfaceId;
    }

    // we do not allow NFTs to be send to this contract, except internally
    function onERC721Received(
        address /*_operator*/,
        address /*_from*/,
        uint256 /*_tokenId*/,
        bytes memory /*_data*/) external view returns (bytes4) {
        if (msg.sender == address(this)) {
            return RECEIVED;
        }
        revert("nope");
    }

    /**
    * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
    * The call is not executed if the target address is not a contract.
    *
    * @param from address representing the previous owner of the given token ID
    * @param to target address that will receive the tokens
    * @param tokenId uint256 ID of the token to be transferred
    * @param _data bytes optional data to send along with the call
    * @return bool whether the call correctly returned the expected magic value
    *
    * credits https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/ERC721.sol
    */
    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) private returns (bool) {
        if (isContract(to)) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, _data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC721: transfer to non ERC721Receiver implementer");
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
            return false; // not needed, but the ide complains that there's "no return statement"
        } else {
            return true;
        }
    }

    /**
     * @dev Returns true if `account` is a contract.
     *
     * credits https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Address.sol
     */
    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    function _intToString(uint256 value) public pure returns (string memory) {
        // Inspired by openzeppelin's implementation - MIT licence
        // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Strings.sol#L15
        // this version removes the decimals counting
        uint8 count;
        if (value == 0) {
            return "0";
        }
        uint256 digits = 31;
        // bytes and strings are big endian, so working on the buffer from right to left
        // this means we won't need to reverse the string later
        bytes memory buffer = new bytes(32);
        while (value != 0) {
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
            digits -= 1;
            count++;
        }
        uint256 temp;
        assembly {
            temp := mload(add(buffer, 32))
            temp := shl(mul(sub(32, count), 8), temp)
            mstore(add(buffer, 32), temp)
            mstore(buffer, count)
        }
        return string(buffer);
    }
}

/**
* DynamicBufferLib adapted from
* https://github.com/Vectorized/solady/blob/main/src/utils/DynamicBufferLib.sol
*/
library DynamicBufferLib {
    /// @dev Type to represent a dynamic buffer in memory.
    /// You can directly assign to `data`, and the `append` function will
    /// take care of the memory allocation.
    struct DynamicBuffer {
        bytes data;
    }

    /// @dev Appends `data` to `buffer`.
    /// Returns the same buffer, so that it can be used for function chaining.
    function append(DynamicBuffer memory buffer, bytes memory data)
    internal
    pure
    returns (DynamicBuffer memory)
    {
        /// @solidity memory-safe-assembly
        assembly {
            if mload(data) {
                let w := not(31)
                let bufferData := mload(buffer)
                let bufferDataLength := mload(bufferData)
                let newBufferDataLength := add(mload(data), bufferDataLength)
            // Some random prime number to multiply `capacity`, so that
            // we know that the `capacity` is for a dynamic buffer.
            // Selected to be larger than any memory pointer realistically.
                let prime := 1621250193422201
                let capacity := mload(add(bufferData, w))

            // Extract `capacity`, and set it to 0, if it is not a multiple of `prime`.
                capacity := mul(div(capacity, prime), iszero(mod(capacity, prime)))

            // Expand / Reallocate memory if required.
            // Note that we need to allocate an exta word for the length, and
            // and another extra word as a safety word (giving a total of 0x40 bytes).
            // Without the safety word, the data at the next free memory word can be overwritten,
            // because the backwards copying can exceed the buffer space used for storage.
                for {} iszero(lt(newBufferDataLength, capacity)) {} {
                // Approximately double the memory with a heuristic,
                // ensuring more than enough space for the combined data,
                // rounding up to the next multiple of 32.
                    let newCapacity :=
                    and(add(capacity, add(or(capacity, newBufferDataLength), 32)), w)

                // If next word after current buffer is not eligible for use.
                    if iszero(eq(mload(0x40), add(bufferData, add(0x40, capacity)))) {
                    // Set the `newBufferData` to point to the word after capacity.
                        let newBufferData := add(mload(0x40), 0x20)
                    // Reallocate the memory.
                        mstore(0x40, add(newBufferData, add(0x40, newCapacity)))
                    // Store the `newBufferData`.
                        mstore(buffer, newBufferData)
                    // Copy `bufferData` one word at a time, backwards.
                        for {let o := and(add(bufferDataLength, 32), w)} 1 {} {
                            mstore(add(newBufferData, o), mload(add(bufferData, o)))
                            o := add(o, w) // `sub(o, 0x20)`.
                            if iszero(o) {break}
                        }
                    // Store the `capacity` multiplied by `prime` in the word before the `length`.
                        mstore(add(newBufferData, w), mul(prime, newCapacity))
                    // Assign `newBufferData` to `bufferData`.
                        bufferData := newBufferData
                        break
                    }
                // Expand the memory.
                    mstore(0x40, add(bufferData, add(0x40, newCapacity)))
                // Store the `capacity` multiplied by `prime` in the word before the `length`.
                    mstore(add(bufferData, w), mul(prime, newCapacity))
                    break
                }
            // Initalize `output` to the next empty position in `bufferData`.
                let output := add(bufferData, bufferDataLength)
            // Copy `data` one word at a time, backwards.
                for {let o := and(add(mload(data), 32), w)} 1 {} {
                    mstore(add(output, o), mload(add(data, o)))
                    o := add(o, w) // `sub(o, 0x20)`.
                    if iszero(o) {break}
                }
            // Zeroize the word after the buffer.
                mstore(add(add(bufferData, 0x20), newBufferDataLength), 0)
            // Store the `newBufferDataLength`.
                mstore(bufferData, newBufferDataLength)
            }
        }
        return buffer;
    }
    /*
        /// @dev Appends `data0`, `data1` to `buffer`.
    /// Returns the same buffer, so that it can be used for function chaining.
    function append(DynamicBuffer memory buffer, bytes memory data0, bytes memory data1)
    internal
    pure
    returns (DynamicBuffer memory)
    {
        return append(append(buffer, data0), data1);
    }
*/
    /// @dev Appends `data0`, `data1`, `data2` to `buffer`.
    /// Returns the same buffer, so that it can be used for function chaining.
    function append(
        DynamicBuffer memory buffer,
        bytes memory data0,
        bytes memory data1,
        bytes memory data2
    ) internal pure returns (DynamicBuffer memory) {
        return append(append(append(buffer, data0), data1), data2);
    }
    /*

        /// @dev Appends `data0`, `data1`, `data2`, `data3` to `buffer`.
    /// Returns the same buffer, so that it can be used for function chaining.
    function append(
        DynamicBuffer memory buffer,
        bytes memory data0,
        bytes memory data1,
        bytes memory data2,
        bytes memory data3
    ) internal pure returns (DynamicBuffer memory) {
        return append(append(append(append(buffer, data0), data1), data2), data3);
    }

    /// @dev Appends `data0`, `data1`, `data2`, `data3`, `data4` to `buffer`.
    /// Returns the same buffer, so that it can be used for function chaining.
    function append(
        DynamicBuffer memory buffer,
        bytes memory data0,
        bytes memory data1,
        bytes memory data2,
        bytes memory data3,
        bytes memory data4
    ) internal pure returns (DynamicBuffer memory) {
        append(append(append(append(buffer, data0), data1), data2), data3);
        return append(buffer, data4);
    }

    /// @dev Appends `data0`, `data1`, `data2`, `data3`, `data4`, `data5` to `buffer`.
    /// Returns the same buffer, so that it can be used for function chaining.
    function append(
        DynamicBuffer memory buffer,
        bytes memory data0,
        bytes memory data1,
        bytes memory data2,
        bytes memory data3,
        bytes memory data4,
        bytes memory data5
    ) internal pure returns (DynamicBuffer memory) {
        append(append(append(append(buffer, data0), data1), data2), data3);
        return append(append(buffer, data4), data5);
    }

    /// @dev Appends `data0`, `data1`, `data2`, `data3`, `data4`, `data5`, `data6` to `buffer`.
    /// Returns the same buffer, so that it can be used for function chaining.
    function append(
        DynamicBuffer memory buffer,
        bytes memory data0,
        bytes memory data1,
        bytes memory data2,
        bytes memory data3,
        bytes memory data4,
        bytes memory data5,
        bytes memory data6
    ) internal pure returns (DynamicBuffer memory) {
        append(append(append(append(buffer, data0), data1), data2), data3);
        return append(append(append(buffer, data4), data5), data6);
    }
    */
}

/**
 * @dev Provides a set of functions to operate with Base64 strings.
 *
 * _Available since v4.5._
 */
library Base64 {
    /**
     * @dev Base64 Encoding/Decoding Table
     */
    string internal constant _TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    /**
     * @dev Converts a `bytes` to its Bytes64 `string` representation.
     */
    function encode(bytes memory data) internal pure returns (string memory) {
        /**
         * Inspired by Brecht Devos (Brechtpd) implementation - MIT licence
         * https://github.com/Brechtpd/base64/blob/e78d9fd951e7b0977ddca77d92dc85183770daf4/base64.sol
         */
        if (data.length == 0) return "";

        // Loads the table into memory
        string memory table = _TABLE;

        // Encoding takes 3 bytes chunks of binary data from `bytes` data parameter
        // and split into 4 numbers of 6 bits.
        // The final Base64 length should be `bytes` data length multiplied by 4/3 rounded up
        // - `data.length + 2`  -> Round up
        // - `/ 3`              -> Number of 3-bytes chunks
        // - `4 *`              -> 4 characters for each chunk
        string memory result = new string(4 * ((data.length + 2) / 3));

        /// @solidity memory-safe-assembly
        assembly {
        // Prepare the lookup table (skip the first "length" byte)
            let tablePtr := add(table, 1)
        // Prepare result pointer, jump over length
            let resultPtr := add(result, 32)
        // Run over the input, 3 bytes at a time
            for {
                let dataPtr := data
                let endPtr := add(data, mload(data))
            } lt(dataPtr, endPtr) {

            } {
            // Advance 3 bytes
                dataPtr := add(dataPtr, 3)
                let input := mload(dataPtr)
            // To write each character, shift the 3 bytes (18 bits) chunk
            // 4 times in blocks of 6 bits for each character (18, 12, 6, 0)
            // and apply logical AND with 0x3F which is the number of
            // the previous character in the ASCII table prior to the Base64 Table
            // The result is then added to the table to get the character to write,
            // and finally write it in the result pointer but with a left shift
            // of 256 (1 byte) - 8 (1 ASCII char) = 248 bits
                mstore8(resultPtr, mload(add(tablePtr, and(shr(18, input), 0x3F))))
                resultPtr := add(resultPtr, 1) // Advance
                mstore8(resultPtr, mload(add(tablePtr, and(shr(12, input), 0x3F))))
                resultPtr := add(resultPtr, 1) // Advance
                mstore8(resultPtr, mload(add(tablePtr, and(shr(6, input), 0x3F))))
                resultPtr := add(resultPtr, 1) // Advance
                mstore8(resultPtr, mload(add(tablePtr, and(input, 0x3F))))
                resultPtr := add(resultPtr, 1) // Advance
            }
            // When data `bytes` is not exactly 3 bytes long
            // it is padded with `=` characters at the end
            switch mod(mload(data), 3)
            case 1 {
                mstore8(sub(resultPtr, 1), 0x3d)
                mstore8(sub(resultPtr, 2), 0x3d)
            }
            case 2 {
                mstore8(sub(resultPtr, 1), 0x3d)
            }
        }
        return result;
    }
}

interface IStogie {
    struct UserInfo {
        uint256 deposit;    // How many LP tokens the user has deposited.
        uint256 rewardDebt; // keeps track of how much reward was paid out
    }
    function farmers(address _user) external view returns (UserInfo memory);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 */
interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/**
 * @title ERC-721 Non-Fungible Token Standard, optional metadata extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
interface IERC721Metadata {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

interface IERC721TokenReceiver {
    function onERC721Received(address _operator, address _from, uint256 _tokenId, bytes memory _data) external returns (bytes4);
}

/// @title ERC-721 Non-Fungible Token Standard, optional enumeration extension
/// @dev See https://eips.ethereum.org/EIPS/eip-721
///  Note: the ERC-165 identifier for this interface is 0x780e9d63.
interface IERC721Enumerable {
    function totalSupply() external view returns (uint256);
    function tokenByIndex(uint256 _index) external view returns (uint256);
    function tokenOfOwnerByIndex(address _owner, uint256 _index) external view returns (uint256);
}
/**
 * @dev Required interface of an ERC721 compliant contract.
 */
interface IERC721 is IERC165, IERC721Metadata, IERC721Enumerable, IERC721TokenReceiver {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
    function approve(address to, uint256 tokenId) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function setApprovalForAll(address operator, bool _approved) external;
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;
}

/**
 * @title ERC721 token receiver interface
 * @dev Interface for any contract that wants to support safeTransfers
 * from ERC721 asset contracts.
 */
interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

interface ICigToken {
    function stakedlpSupply() external view returns (uint256);
    function taxBurnBlock() external view returns (uint256);
    function The_CEO() external view returns (address);
}

interface IPunkIdenticons {
    function pick(
        address _a,
        uint64 _cid) view external returns (bytes32[] memory);

}

interface IPunkBlocks {
    function svgFromKeys(
        bytes32[] calldata _attributeKeys,
        uint16 _x,
        uint16 _y,
        uint16 _size,
        uint32 _orderID) external view returns (string memory);
}

interface IBarcode {
    function draw(
        uint256 _in,
        string memory _x,
        string memory _y,
        string memory _color,
        uint16 _height,
        uint8 _barWidth) view external returns (string memory);
}