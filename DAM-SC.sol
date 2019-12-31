pragma solidity ^ 0.4 .16;
contract DataStore {
  enum DataStatus {
    ForSale,
    Sold,
    Unsold
  }
  enum DataCondition {
    New,
    Old
  }
  uint public dataIndex;
  mapping(address => mapping(uint => Data)) stores;
  mapping(uint => address) dataIdInStore;
  hB[] public highestBidders;
  mapping(address => uint) public bidderId;
  uint startPrice;

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

  function DataStore() public {
    dataIndex = 0;
  }

  function numberOfItems() public returns(uint) {
    return dataIndex;
  }

  event sellCast(address seller, uint dataId, uint value);
  event bidCast(address bidder, uint dataId, uint value);
  event NewData(uint DATAId, string Name, string Category, string ImageLink, string DescLink,
    uint AuctionStartTime, uint AuctionEndTime, uint DATACondition);

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

  function totalBids(uint DATAId) public returns(uint) {
    Data memory data = stores[dataIdInStore[DATAId]][DATAId];
    return data.totalBids;
  }

  function stringToUint(string s) public returns(uint) {
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
  function getData(uint DATAId) public returns(uint, string, string, string, string, uint, uint, DataStatus, DataCondition) {
    Data memory data = stores[dataIdInStore[DATAId]][DATAId];
    return (data.id, data.name, data.category, data.imageLink, data.descLink, data.auctionStartTime,
      data.auctionEndTime, data.status, data.condition);
  }
}
