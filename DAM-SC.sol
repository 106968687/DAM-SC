pragma solidity 0.5.16;
contract DataAuction {
  enum DataStatus {ForSale, Sold, Unsold}
  enum DataCondition {New, Old}
  uint public dataIndex;
  mapping(address => mapping(uint => Data)) public stores;
  mapping(uint => address) public dataIdInStore;
  hB[] public highestBidders;
  mapping(address => uint) public bidderId;
  uint public startPrice;
  uint public deposit;
  address public DSaddress;
  mapping (address => DB) public databuyers;
  enum DBStatus {DBDeposited, SuccessfulAuction, Unsatisfied, AuctionCompleted, Refunded}
  address public DBaddress;
  enum SCStatus {WaitingforDB, Aborted}
  SCStatus public status;
  uint public numberOfDBs;
  uint public highestBid;
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

  constructor() public {
    dataIndex = 0;
    deposit = 3 ether;
    status = SCStatus.WaitingforDB;
    numberOfDBs = 0;    
  }

  function numberOfItems() view external returns(uint) {
    return dataIndex;
  }

  function payDeposit() DSDeposit external payable{
    require(msg.sender == DSaddress);
    DSDeposited("DS has paid a deposit.", DSaddress);
  }

  function requestBidData() OnlyDB DBCost external payable{
    require(status == SCStatus.WaitingforDB);
    databuyers[msg.sender].status = DBStatus.DBDeposited;
    DBDeposited(msg.sender, "DB has paid a deposit.");
    numberOfDBs++;
  }

  function DBRefund() OnlyDB external payable {
	require(databuyers[msg.sender].status == DBStatus.DBDeposited);
    msg.sender.transfer(deposit);
    databuyers[msg.sender].status = DBStatus.Refunded;
    refundBasedonDBRequest("The data buyer has been refunded.", msg.sender);
  }

  function sell(uint DATAId, bytes32 SELL) external payable returns(bool) {
    Data storage data = stores[dataIdInStore[DATAId]][DATAId];
    require(now >= data.auctionStartTime);
    require(now <= data.auctionEndTime);
    require(data.sells[msg.sender][SELL].seller == 0);
    sellCast(msg.sender, DATAId, msg.value);
    data.sells[msg.sender][SELL] = Sell(msg.sender, DATAId, SELL, false);
    return true;
  }

  function bid(uint DATAId, bytes32 BID) external payable returns(bool) {
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

  function revealSell(uint DATAId, string SellerPrice, string Secret) external {
    Data storage data = stores[dataIdInStore[DATAId]][DATAId];
    require(now > data.auctionEndTime);
    bytes32 sealedSell = keccak256(abi.encodePacked(SellerPrice, Secret));
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

  function revealBid(uint DATAId, string Amount, string Secret, string SellerPrice) external {
    Data storage data = stores[dataIdInStore[DATAId]][DATAId];
    require(now > data.auctionEndTime);
    bytes32 sealedBid = keccak256(abi.encodePacked(Amount, Secret));
    Bid memory bidInfo = data.bids[msg.sender][sealedBid];
    require(bidInfo.bidder > 0);
    require(bidInfo.revealed == false);
    uint refund;
    uint amount = stringToUint(Amount);
    uint sellerPrice = stringToUint(SellerPrice);
    bidderId[msg.sender] = highestBidders.length;
    uint id = bidderId[msg.sender];    
    if (sellerPrice == startPrice) {
      if (bidInfo.value < amount || amount < sellerPrice) {
        refund = bidInfo.value;
      } else {
        if (amount > data.highestBid) {
          data.highestBidder = msg.sender;
          data.highestBid = amount;
          for (uint i = 0; i < 10; i++) {
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

  function highestBidderInfo(uint DATAId) external returns(address[]) {
    address[] memory adrs = new address[](10);
    Data storage data = stores[dataIdInStore[DATAId]][DATAId];
    uint counter = 0;
    for (uint i = 0; i < 10; i++) {
      data.highestBidder = highestBidders[i].highestBidder;
      adrs[counter] = data.highestBidder;
      counter++;
    }
    return adrs;
  }

  function totalBids(uint DATAId) view external returns(uint) {
    Data memory data = stores[dataIdInStore[DATAId]][DATAId];
    return data.totalBids;
  }

  function stringToUint(string s) pure external returns(uint) {
    bytes memory b = bytes(s);
    uint res = 0;
    for (uint i = 0; i < 100; i++) {
      if (b[i] >= 48 && b[i] <= 57) {
        res = res * 10 + (uint(b[i]) - 48);
      }
    }
    return res;
  }

  function addDataToStore(string Name, string Category, string ImageLink, string DescLink, uint AuctionStartTime, uint AuctionEndTime, uint DATACondition) external {
    require(AuctionStartTime < AuctionEndTime);
    dataIndex += 1;
    Data memory data = Data(dataIndex, Name, Category, ImageLink, DescLink, AuctionStartTime, AuctionEndTime, 0, 0, 0, DataStatus.ForSale, DataCondition(DATACondition));
    stores[msg.sender][dataIndex] = data;
    dataIdInStore[dataIndex] = msg.sender;
    NewData(dataIndex, Name, Category, ImageLink, DescLink, AuctionStartTime, AuctionEndTime, DATACondition);
  }

  function getData(uint DATAId) view external returns(uint, string, string, string, string, uint, uint, DataStatus, DataCondition) {
    Data memory data = stores[dataIdInStore[DATAId]][DATAId];	
    return (data.id, data.name, data.category, data.imageLink, data.descLink, data.auctionStartTime,
      data.auctionEndTime, data.status, data.condition);
  }

  function payBid(address databuyer) OnlyDB DBPay external payable{    
	for (uint i = 0; i < 10; i++) {
      if (databuyer == highestBidders[i].highestBidder){
        DBPaid("DB has paid the bid.", msg.sender);
        generateToken(databuyer, timeliness);
      }
    }
  }

  function generateToken(address databuyer,uint Timeliness) internal{
        bytes32 token = keccak256(abi.encodePacked(databuyer,DSaddress,block.timestamp,Timeliness));
        databuyers[databuyer].token = token;
        tokenGeneratedforDB(databuyer, token, block.timestamp, timeliness);
    }

  function DBComfirmedResult(int result) OnlyDB external{
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

  function downloadResolutionAndPayment(address databuyer, bool arbitrationResult) OnlyABR external payable{
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

  function qualityResolutionAndPayment(address databuyer, bool arbitrationResult) OnlyABR external payable{
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
