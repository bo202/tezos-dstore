(*// SPDX-License-Identifier: MIT
--------------------------------------------------
WARNING: 
This contract should not run in a production environment since it 
has not been audited for security concerns.  It is presented as is.

END WARNING
--------------------------------------------------

This contract implements a distributed store.  Sellers can list things for sell.
Each product for sell is identified by its productId.  If this is a bookstore,
the productId can be the book's ISBN for example.

The store is abstracted by the catalogue, a big map mapping from product Id to a market map.

The market map is a mapping from seller addresses to a product details.  

Product details tracks the following for a seller:
- unitPrice
- supply
- balance of the seller


To compile the contract:

sudo docker run --rm -v "$PWD":"$PWD" -w "$PWD" ligolang/ligo:0.31.0 compile-contract dStore.mligo main --output-file=dStore.tz
or
ligo compile contract dStore.mligo  --entry-point main --output-file dStore.tz

Examples

Here is an initial storage example:

Big_map.literal [ 
 123, Map.literal [("tz1..":address), { unitPrice=1tez; supply=10n; balance=0tez}]
]

A seller calling the Sell entrypoint to sell an additional quantity:

Sell {  seller=("tz...": address); 
        prodId=123;
        quantity=1n;
        unitPrice=1tez}

The resulting catalogue shows :
( LIST_EMPTY() , 
MAP_ADD(123 , MAP_ADD(@"tz..." , record[balance -> 0mutez ,
supply -> +11 , unitPrice -> 1000000mutez] , MAP_EMPTY()) , BIG_MAP_EMPTY()) )

Note the unitPrice will be overwritten if the seller provided a different unitPrice.

*)
(* 
The productId identifies a book for sale.
This can be for example a books ISBN.
The productId is stored as an int for simplicity, assume 
there are not dashes or spaces.
*)
type productId = int

(*
A product, e.g. a book, has a unit price, this price for buying
one product, and a supply, this is the number of the product available.
Balance shows amount earned by seller form selling this product.
*)
type product = {
    unitPrice: tez;
    supply   : nat;
    balance  : tez;
}


(*
Market is a storage for each seller, how many units they have to sell,
and the unit price.

ASSUMPTION: This storage assumes each seller of one product
sells all units of that product at the same price.
*)

type market = (address, product) map

(*
The catalogue tracks for each productId, its market.

ASSUMPTION: The catalogue stores the productId, which identifies the product,
but for simplicity and to save store, no additional meta data about the product
is tracked in this contract.  Thus, this contract is an "abstract distributed store".
If this information is needed, another contract or
database should track for each productId what meta information needed.

*)

type catalogue = (productId, market) big_map


(*
An order is a type of struct that represents a buy or sell.
If buy, seller address is 0, quantity is the amount to buy.
If sell, unitPrice must be specified by the seller, quantity is the supply for sell.
*)
type order = {
    seller    : address;
    prodId    : productId;
    quantity  : nat;
    unitPrice : tez;
}

type action =   Buy  of order |
                Sell of order |
                Withdraw of (address * productId)

type parameter = action
type storage   = catalogue

(* ----------------------------------------------------------
The buy() function will buy order.productId from order.seller.
*)
let buy(orderInput, s: order * storage): operation list * storage =
    // Look for prodId in the catalogue to get the market
    let s: storage = match Big_map.find_opt orderInput.prodId s with
        | None -> (failwith "ERROR: Product Id not found.": storage)
        | Some m -> 
            let prodFromSeller : product = match Map.find_opt orderInput.seller m with
                | None -> (failwith "ERROR: Seller not found.": product)
                | Some prod ->  (*  Ensure the quantity specified in the order
                                    is less than the available supply from this seller.
                                    Update product struct to reflect decreased supply
                                    increased balance for seller.
                                *)
                                let () = if prod.supply < orderInput.quantity then
                                    (failwith "Insufficient supply to meet order")
                                in
                               
                                { prod with 
                                    supply  = abs(prod.supply-orderInput.quantity);
                                    balance = prod.balance + Tezos.amount 
                                }
            in
            let m = Map.update orderInput.seller (Some prodFromSeller) m 
            in 
            Big_map.update orderInput.prodId (Some (m) ) s
    in 
    ([]: operation list), s

(* ----------------------------------------------------------
The sell() function will list for sell order.productId from order.seller.
*)
let sell(orderInput, s: order * storage): operation list * storage=
    let s: storage = match Big_map.find_opt orderInput.prodId s with
        | None -> // Add this product Id to catalogue.
            let newProd : product = {
                                        unitPrice= orderInput.unitPrice;
                                        supply   = orderInput.quantity;
                                        balance  = 0tez;
                                    }
            in
            let m : market = Map.literal[((orderInput.seller:address), newProd)]
            in
            Big_map.add orderInput.prodId m s
        | Some m -> // The dStore has a listing for this product Id so update the market
            let prodFromSeller : product = match Map.find_opt orderInput.seller m with
            | None ->// Add a new seller to this market.
                    {
                        unitPrice = orderInput.unitPrice;
                        supply    = orderInput.quantity;
                        balance   = 0tez;
                    }
            
            | Some prod -> // Seller is already selling this product, and has MORE to sell.
                    
                    {prod with 
                        unitPrice = orderInput.unitPrice;
                        supply    = prod.supply + orderInput.quantity
                    }
            in 
            let m = Map.update orderInput.seller (Some prodFromSeller) m
            in
            Big_map.update orderInput.prodId (Some m) s


    in 
    ([]: operation list), s

(* ----------------------------------------------------------
The withdraw function allows the seller to withdraw their money.
*)
let withdraw(seller, prodId, s: address * productId * storage): operation list * storage =
    
    let sellerMarket: market = match Big_map.find_opt prodId s with
        | None -> (failwith "Product Id not found.": market)
        | Some m -> m
    in
    let sellerProduct: product = match Map.find_opt seller sellerMarket with
        | None -> (failwith "Seller not found.": product)
        | Some p -> p
    in 
    // Set amount of tez to withdraw
    // The owner takes a store fee of 1%
    let storeFee = sellerProduct.balance / 100n 
    in
    let balanceToWithdraw : tez = sellerProduct.balance - storeFee
    in
    
    (*
    Update the catalogue as follows: 
    - If balance=0tez or supply=0, delete seller from sellerMarket
    - Othewise, set seller's balance in catalogue to 0tez
    Since the product is removed from the catalogue, if a record is needed, it should be kept elsewhere.
    *)
    let sellerMarket: market = 
        if sellerProduct.supply=0n then
            Map.remove seller sellerMarket
        else
            Map.update seller (Some {sellerProduct with balance=0tez}) sellerMarket

    in
    // Remove the product Id to remove listing if market has no sellers
    let s: storage = 
        if Map.size(sellerMarket) = 0n then
            Big_map.remove prodId s 
        else
            Big_map.update prodId (Some sellerMarket) s
    in

    
    let ownerAddress: address = ("tz1PJRkMj8A7NQanYEdpaAHw8iCgvZYTPgvp": address)
    in
    let ownerContract : unit contract = 
        match (Tezos.get_contract_opt ownerAddress: unit contract option) with
        | Some contract -> contract
        | None -> (failwith "Not a contract" : unit contract)
    in 
    let sellerContract : unit contract = 
        match (Tezos.get_contract_opt seller : unit contract option) with
        | Some contract -> contract
        | None          -> (failwith "Not a contract" : unit contract)
    in
     
    let sellerWithdraw: operation = Tezos.transaction unit balanceToWithdraw sellerContract
    in 
    let payFee: operation = Tezos.transaction unit storeFee ownerContract
    in 
    [sellerWithdraw; payFee], s

(* --------------------------------------------
Main function.

The main function branches to two entrypoints, 
- one for listing something to sell,
- another for buying something.
- the seller can withdraw the money from their sells.
These two entrypoints will update the catalogue in their respective ways.
*)
let main(p, s : parameter * storage): operation list * storage =
match p with 
        | Buy  orderInput -> buy (orderInput, s)
        | Sell orderInput -> sell(orderInput, s)
        | Withdraw key -> withdraw(key.0, key.1, s)