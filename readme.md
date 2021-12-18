# A Distributed Store on the Blockchain

This smart contract `dStore.mligo` implements functions of a distributed store, such as a book store.  It has functions for buy, selling, and withdrawing a seller's balance.

The `order` struct is used to provide the information needed to carry out a buy or sell.  It takes:

* a seller's `address`,
* the product's Id `prodId`, for example a books ISBN,
* the quantity to buy or sell,
* the unit price to  pay.
If the order is a buy, the seller's address specifies the seller to buy from.  If the order is a sell, the seller's address specifies who is selling.

The store is represented by the big map `catalogue`.  This is a map from a product Id to another map called the `market`.

The `market` map is a mapp from seller addresses to the a `product` struct which specifies a product's details.  The `product` struct keeps the following details:

* `unitPrice`: the price to transact,
* `supply`: how many is available,
* `balance`: the money, in tez, the seller has made so far.

To save space, the catalogue will not keep too much other details about the products.  Another database can be used to track a product's details.
## Example Storage and Operation
The following is an example initial storage:
    
    Big_map.literal [ 
        123, Map.literal [("tz...":address), { unitPrice=1tez; supply=10n; balance=10tez}]
    ]
## Listing items for Sell
If a seller wants to list something for sell, they can use the Sell endpoint as follows:

    Sell {seller=("tz...": address); prodId=123; quantity=10n; unitPrice=1tez}
    
If the productId is not in the `catalogue`, or if the seller's address is not in the `market`, then this is a new listing.  Otherwise, this is an update of an existing listing, `unitPrice` and `supply` fields are overwritten.

Using the above example storage, running on LIGO playground gives the following returned (empty) operations list and updated map:

    ( LIST_EMPTY() , MAP_ADD(123 , MAP_ADD(@"tz..." , record[balance -> 10000000mutez , supply -> +10 , unitPrice -> 1000000mutez] , MAP_EMPTY()) , 
    MAP_ADD(124 , MAP_ADD(@"tz..." , record[balance -> 0mutez , supply -> +10 , unitPrice -> 2000000mutez] , MAP_EMPTY()) , BIG_MAP_EMPTY())) )

## Buying from the Catalogue

If a buyer wants to buy from the catalogue, they can use the Buy entrypoint:

    Buy {seller=("tz...": address); prodId=123; quantity=10n; unitPrice=1tez}
    
Here, the order given is the same as the sell order, but it has different meanings.  The seller is who the buyer wants to buy from, the product Id, `prodId`, identifies the product, `quantity` specifies how many to buy, and unitPrice is the product's unit price as before.

Using LIGO playground, the returned (empty) operations list and updated is as follows:

    ( LIST_EMPTY() , MAP_ADD(123 , MAP_ADD(@"tz..." , record[balance -> 10000000mutez , supply -> +0 , unitPrice -> 1000000mutez] , MAP_EMPTY()) , BIG_MAP_EMPTY()) )
    
Note that the catalogue now shows no more supply, but the balance is non-zero since seller has to call withdraw separately.

## Withdrawing

If a seller wants to withdraw the balance from their sales from the catalogue, they can use the Withdraw entrypoint:

    Withdraw (("tz...": address), 123)

When withdrawing, the current implementation takes a 1% store fee, and pays the seller 99%.

Using LIGO playground, a dry run returns the following withdraw operation and new catalogue:
    
    (
    CONS(Operation(0135a1ec49145785df89178dcb6e96c9a9e1e71e0a00000001e09fdc04000002298c03ed7d454a101eb7022bc95f7e5f41ac7800) ,
    
    CONS(Operation(0135a1ec49145785df89178dcb6e96c9a9e1e71e0a00000101a08d060000282b6e1122d7da80e023828016518e4e041cd87500) , LIST_EMPTY())) , 

    MAP_ADD(123 , MAP_ADD(@"tz..." , record[balance -> 0mutez , supply -> +10 , unitPrice -> 1000000mutez] , MAP_EMPTY()) , BIG_MAP_EMPTY()) 
    
    )
    
If the supply is 0, then after withdraw, that market is deleted, and if the market mapping is empty, determined using `Map.size(...)`, the product listing is also deleted:

    (
    CONS(Operation(0135a1ec49145785df89178dcb6e96c9a9e1e71e0a00000001e09fdc04000002298c03ed7d454a101eb7022bc95f7e5f41ac7800) ,
    CONS(Operation(0135a1ec49145785df89178dcb6e96c9a9e1e71e0a00000101a08d060000282b6e1122d7da80e023828016518e4e041cd87500) , LIST_EMPTY())) , 
    BIG_MAP_EMPTY() 
    
    )

## Future Work

The dStore needs a governance protocol to prevent illegal products from being sold.  Also, a reputation score is needed for the seller.  Also needed are a database to track product sales, and product information.
