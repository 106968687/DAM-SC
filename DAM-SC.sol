pragma solidity ^ 0.4 .16;
contract DataAuction {
  enum DataStatus {ForSale, Sold, Unsold}
  enum DataCondition {New, Old}
  uint public dataIndex;
  mapping(address => mapping(uint => Data)) stores;
  mapping(uint => address) dataIdInStore;
  hB[] public highestBidders;
  mapping(address => uint) public bidderId;
  uint startPrice;
  uint public deposit;
  address public DSaddress;
  mapping (address => DB) public databuyers;
  enum DBStatus {DBDeposited, SuccessfulAuction, Unsatisfied, AuctionCompleted, Refunded}
  address public DBaddress;
  enum SCStatus {WaitingforDB, Aborted}
  SCStatus public status;
  uint numberOfDBs;
  uint highestBid;
  uint public timeliness = 7;
  address public ABRaddress;
  address public DTCaddress;

  struct DB {
      DBStatus status;
      int result;
      bytes32 token;
  }
  struct Data {
    uint id;
    string name;
    string category;
    string imageLink;
    string descLink;
    uint auctionStartTime;
    uint auctionEndTime;
    address highestBidder;
    uint highestBid;
    uint totalBids;
    DataStatus status;
    DataCondition condition;
    mapping(address => mapping(bytes32 => Bid)) bids;
    mapping(address => mapping(bytes32 => Sell)) sells;
  }
  struct hB {
    address highestBidder;
    uint dataId;
    uint highestBid;
  }
  struct Bid {
    address bidder;
    uint dataId;
    uint value;
    bool revealed;
  }
  struct Sell {
    address seller;
    uint dataId;
    bytes32 value;
    bool revealed;
  }

  modifier DSDeposit(){
    require(msg.value == deposit);
    _;
  }

  modifier OnlyDB(){
    require(msg.sender == DBaddress);
    _;
  }

  modifier DBCost(){
    require(msg.value == deposit);
    _;
  }

  modifier DBPay(){
    require(msg.value == highestBid);
    _;
  }

  modifier OnlyABR(){
      require(msg.sender == ABRaddress);
      _;
  }

  event sellCast(address seller, uint dataId, uint value);
  event bidCast(address bidder, uint dataId, uint value);
  event NewData(uint DATAId, string Name, string Category, string ImageLink, string DescLink,
    uint AuctionStartTime, uint AuctionEndTime, uint DATACondition);
  event DSDeposited(string info,address datapurchaser);
  event DBDeposited(address databuyer, string info);
  event tokenGeneratedforDB(address databuyer, bytes32 token, uint timestamp, uint duration);
  event successfulAuction(address databuyer);
  event dataCannotDownload(address databuyer, string info);
  event ABRIsVerifyingforDB(address databuyer, string info, bytes32 token);
  event dataUnavailable(address databuyer, string info);
  event CouldNotDownload(address databuyer, string info);
  event refundDone(address databuyer);
  event Unavailable(address databuyer, string info);
  event refundBasedonDBRequest(string info, address databuyer);
  event DBPaid(string info, address databuyer);
  event paymentSettled(address databuyer, string info);

  function DataAuction() public {
    dataIndex = 0;
    deposit = 3 ether;
    status = SCStatus.WaitingforDB;
    numberOfDBs = 0;
    DTCaddress = 0xd813351258D8A53314E55b12c3Cf11C98dA8E7D4;
    ABRaddress = 0xd06B32822f5F1838E0Bb05CBEC803889eFDd9380;
    DSaddress = 0x09BdFdBAc10253e988b4c7197f0faf44Ea7F8479;
   //DBaddress = 0x9549E34316ab06B205711B2eF1Ea5D078C6e8E5f;
  }

  function numberOfItems() view public returns(uint) {
    return dataIndex;
  }

  function payDeposit() DSDeposit public payable{
    require(msg.sender == DSaddress);
    DSDeposited("DS has paid a deposit.", DSaddress);
  }

  function requestBidData() OnlyDB DBCost payable public{
    require(status == SCStatus.WaitingforDB);
    databuyers[msg.sender].status = DBStatus.DBDeposited;
    DBDeposited(msg.sender, "DB has paid a deposit.");
    numberOfDBs++;
  }

  function DBRefund() OnlyDB public payable{
	require(databuyers[msg.sender].status == DBStatus.DBDeposited);
    msg.sender.transfer(deposit);
    databuyers[msg.sender].status = DBStatus.Refunded;
    refundBasedonDBRequest("The data buyer has been refunded.", msg.sender);
  }

  function sell(uint DATAId, bytes32 SELL) public payable returns(bool) {
    Data storage data = stores[dataIdInStore[DATAId]][DATAId];
    require(now >= data.auctionStartTime);
    require(now <= data.auctionEndTime);
    require(data.sells[msg.sender][SELL].seller == 0);
    sellCast(msg.sender, DATAId, msg.value);
    data.sells[msg.sender][SELL] = Sell(msg.sender, DATAId, SELL, false);
    return true;
  }

  function bid(uint DATAId, bytes32 BID) public payable returns(bool) {
    Data storage data = stores[dataIdInStore[DATAId]][DATAId];
    require(now >= data.auctionStartTime);
    require(now <= data.auctionEndTime);
    require(msg.value > 0);
    require(data.bids[msg.sender][BID].bidder == 0);
    bidCast(msg.sender, DATAId, msg.value);
    data.bids[msg.sender][BID] = Bid(msg.sender, DATAId, msg.value, false);
    data.totalBids += 1;
    return true;
  }

  function revealSell(uint DATAId, string SellerPrice, string Secret) public {
    Data storage data = stores[dataIdInStore[DATAId]][DATAId];
    require(now > data.auctionEndTime);
    bytes32 sealedSell = keccak256(SellerPrice, Secret);
    Sell memory sellInfo = data.sells[msg.sender][sealedSell];
    require(sellInfo.revealed == false);
    uint amount = stringToUint(SellerPrice);
    if (sellInfo.value == sealedSell) {
      msg.sender.transfer(amount);
      data.sells[msg.sender][sealedSell].revealed = true;
    }
    sellCast(msg.sender, DATAId, amount);
    startPrice = amount;
  }

  function revealBid(uint DATAId, string Amount, string Secret, string SellerPrice) public {
    Data storage data = stores[dataIdInStore[DATAId]][DATAId];
    require(now > data.auctionEndTime);
    bytes32 sealedBid = keccak256(Amount, Secret);
    Bid memory bidInfo = data.bids[msg.sender][sealedBid];
    require(bidInfo.bidder > 0);
    require(bidInfo.revealed == false);
    uint refund;
    uint amount = stringToUint(Amount);
    uint sellerPrice = stringToUint(SellerPrice);

    bidderId[msg.sender] = highestBidders.length;
    uint id = bidderId[msg.sender];
    highestBidders.length++;

    if (sellerPrice == startPrice) {
      if (bidInfo.value < amount || amount < sellerPrice) {
        // Because the bidder didn't pay enough money, he/she lost the bid directly.
        refund = bidInfo.value;
      } else {
        if (amount > data.highestBid) {
          data.highestBidder = msg.sender;
          data.highestBid = amount;
          for (uint i = 0; i < highestBidders.length; i++) {
            highestBidders[i] = highestBidders[highestBidders.length - 1];
            delete highestBidders[i];
          }

          highestBidders[id] = hB({
            highestBidder: msg.sender,
            dataId: DATAId,
            highestBid: amount
          });
          refund = bidInfo.value - amount;

        } else if (amount == data.highestBid) {
          highestBidders[id] = hB({
            highestBidder: msg.sender,
            dataId: DATAId,
            highestBid: amount
          });
          refund = bidInfo.value - amount;

        } else {
          refund = bidInfo.value;
        }

        if (refund > 0) {
          msg.sender.transfer(refund);
          data.bids[msg.sender][sealedBid].revealed = true;
        }
      }
    }
  }

  function highestBidderInfo(uint DATAId) public returns(address[]) {
    address[] memory adrs = new address[](10);
    Data storage data = stores[dataIdInStore[DATAId]][DATAId];
    uint counter = 0;
    for (uint i = 0; i < highestBidders.length; i++) {
      data.highestBidder = highestBidders[i].highestBidder;
      adrs[counter] = data.highestBidder;
      counter++;
    }
    return adrs;
  }

  function totalBids(uint DATAId) view public returns(uint) {
    Data memory data = stores[dataIdInStore[DATAId]][DATAId];
    return data.totalBids;
  }

  function stringToUint(string s) pure public returns(uint) {
    bytes memory b = bytes(s);
    uint res = 0;
    for (uint i = 0; i < b.length; i++) {
      if (b[i] >= 48 && b[i] <= 57) {
        res = res * 10 + (uint(b[i]) - 48);
      }
    }
    return res;
  }

  //Add data products to blockchain
  function addDataToStore(string Name, string Category, string ImageLink, string DescLink, uint AuctionStartTime, uint AuctionEndTime, uint DATACondition) public {
    require(AuctionStartTime < AuctionEndTime);
    dataIndex += 1;
    Data memory data = Data(dataIndex, Name, Category, ImageLink, DescLink, AuctionStartTime, AuctionEndTime, 0, 0, 0, DataStatus.ForSale, DataCondition(DATACondition));
    stores[msg.sender][dataIndex] = data;
    dataIdInStore[dataIndex] = msg.sender;
    NewData(dataIndex, Name, Category, ImageLink, DescLink, AuctionStartTime, AuctionEndTime, DATACondition);
  }

  //Querying data from the blockchain
  function getData(uint DATAId) view public returns(uint, string, string, string, string, uint, uint, DataStatus, DataCondition) {
    Data memory data = stores[dataIdInStore[DATAId]][DATAId];
    return (data.id, data.name, data.category, data.imageLink, data.descLink, data.auctionStartTime,
      data.auctionEndTime, data.status, data.condition);
  }

  function payBid(address databuyer) OnlyDB DBPay() public payable{
    for (uint i = 0; i < highestBidders.length; i++) {
      if (databuyer == highestBidders[i].highestBidder){
        DBPaid("DB has paid the bid.", msg.sender);
        generateToken(databuyer, timeliness);
      }
    }
  }

  function generateToken(address databuyer,uint Timeliness) internal{
        bytes32 token = keccak256(databuyer,DSaddress,block.timestamp,Timeliness);
        databuyers[databuyer].token = token;
        tokenGeneratedforDB(databuyer, token, block.timestamp, timeliness);
    }

  function DBComfirmedResult(int result) OnlyDB public{
    if(result == 1){
      successfulAuction(msg.sender);
      databuyers[msg.sender].status = DBStatus.SuccessfulAuction;
      settlement(msg.sender);
    }
    else if(result == 2){
      dataCannotDownload(msg.sender,"The data resource can not be downloaded.");
      databuyers[msg.sender].status = DBStatus.Unsatisfied;
      ABRIsVerifyingforDB(msg.sender, "Token: ", databuyers[msg.sender].token);
    }
    else if(result == 3){
  		dataUnavailable(msg.sender, "The data resource is inconsistent with its description");
  		databuyers[msg.sender].status = DBStatus.Unsatisfied;
      ABRIsVerifyingforDB(msg.sender, "Off-chain testing data and Token: ", databuyers[msg.sender].token);
  	}
  }

  function downloadResolutionAndPayment(address databuyer, bool arbitrationResult) OnlyABR public payable{
    require(databuyers[databuyer].status == DBStatus.Unsatisfied);
    if(arbitrationResult){
      CouldNotDownload(databuyer, "The data auction is failed.");
      uint x = deposit;
      uint y = highestBid;
      DTCaddress.transfer(x);
      databuyer.transfer(y);
      refundDone(databuyer);
      databuyers[databuyer].status = DBStatus.AuctionCompleted;
    }
    else{
      successfulAuction(databuyer);
      databuyers[databuyer].status = DBStatus.SuccessfulAuction;
      settlement(databuyer);
    }
  }

  function qualityResolutionAndPayment(address databuyer, bool arbitrationResult) OnlyABR public payable{
    require(databuyers[databuyer].status == DBStatus.Unsatisfied);
    if(arbitrationResult){
      Unavailable(databuyer, "The data auction is failed.");
      uint x = deposit;
      uint y = highestBid;
      DTCaddress.transfer(x);
      databuyer.transfer(y);
      refundDone(databuyer);
      databuyers[databuyer].status = DBStatus.AuctionCompleted;
    }
    else{
      successfulAuction(databuyer);
      databuyers[databuyer].status = DBStatus.SuccessfulAuction;
      settlement(databuyer);
    }
  }

  function settlement(address databuyer) internal{
    require(databuyers[databuyer].status == DBStatus.SuccessfulAuction);
    uint x = deposit;
    uint y = highestBid/3;
    ABRaddress.transfer(y);
    DTCaddress.transfer(y);
	DSaddress.transfer(x+y);
    paymentSettled(databuyer, "Settlement has done successfully.");
    databuyers[databuyer].status = DBStatus.AuctionCompleted;
  }
}
