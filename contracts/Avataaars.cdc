/*!
* Avataaars (@dicebear/avataaars)
*
* Code licensed under MIT License.
* Copyright (c) 2023 Florian Körner
*
* Design "Avataaars" by Pablo Stanley licensed under Free for personal and commercial use. / Remix of the original.
* Source: https://avataaars.com/
* Homepage: https://twitter.com/pablostanley
* License: https://avataaars.com/
*/

/* 
*
*  This is an example implementation of a Flow Non-Fungible Token
*  It is not part of the official standard but it assumed to be
*  similar to how many NFTs would implement the core functionality.
*
*/

import "NonFungibleToken"
import "MetadataViews"
import "ViewResolver"
import "FungibleToken"

import "Components"

access(all) contract Avataaars: NonFungibleToken {

    /// Total supply of Avataaarss in existence
    access(all) var totalSupply: UInt64

    access(all) var imageBaseURL: String

    /// The event that is emitted when the contract is created
    access(all) event ContractInitialized()

    /// The event that is emitted when an NFT is withdrawn from a Collection
    access(all) event Withdraw(id: UInt64, from: Address?)

    /// The event that is emitted when an NFT is deposited to a Collection
    access(all) event Deposit(id: UInt64, to: Address?)

    /// Storage and Public Paths
    access(all) let CollectionStoragePath: StoragePath
    access(all) let CollectionPublicPath: PublicPath
    access(all) let CollectionProviderPath: PrivatePath
    access(all) let MinterStoragePath: StoragePath

    // We only have a public path for minting to let Avataaars be like a facuet.
    access(all) let MinterPublicPath: PublicPath

    /// The core resource that represents a Non Fungible Token. 
    /// New instances will be created using the NFTMinter resource
    /// and stored in the Collection resource
    ///
    access(all) resource NFT: NonFungibleToken.NFT {
        
        /// The unique ID that each NFT has
        access(all) let id: UInt64
        access(all) let renderer: Components.Renderer
        access(all) let data: {String: AnyStruct} // any extra data like a name or mint time
    
        init(
            id: UInt64,
            renderer: Components.Renderer
        ) {
            self.id = id
            self.renderer = renderer
            self.data = {}

            // we save the pre-rendered svg for now so that we can vend this svg to third parties.
            // in the future, when there is an implementation of MetadataViews.File
            let rendered = self.renderer.build()
            Avataaars.account.storage.save(rendered, to: StoragePath(identifier: "Avataaars_".concat(id.toString()))!)
        }

        /// Function that returns all the Metadata Views implemented by a Non Fungible Token
        ///
        /// @return An array of Types defining the implemented views. This value will be used by
        ///         developers to know which parameter to pass to the resolveView() method.
        ///
        access(all) view fun getViews(): [Type] {
            return [
                Type<MetadataViews.Display>(),
                Type<MetadataViews.Royalties>(),
                Type<MetadataViews.Editions>(),
                Type<MetadataViews.ExternalURL>(),
                Type<MetadataViews.NFTCollectionData>(),
                Type<MetadataViews.NFTCollectionDisplay>(),
                Type<MetadataViews.Serial>(),
                Type<MetadataViews.Traits>()
            ]
        }

        /// Function that resolves a metadata view for this token.
        ///
        /// @param view: The Type of the desired view.
        /// @return A structure representing the requested view.
        ///
        access(all) fun resolveView(_ view: Type): AnyStruct? {
            switch view {
                case Type<MetadataViews.Display>():
                    return MetadataViews.Display(
                        name: "Avataaars #".concat(self.id.toString()),
                        description: "This is a procedurally generated avatar! You can learn more about it here: https://avataaars.com/",
                        thumbnail: MetadataViews.HTTPFile(
                            url: Avataaars.imageBaseURL.concat(self.id.toString())
                        )
                    )
                case Type<MetadataViews.Editions>():
                    // There is no max number of NFTs that can be minted from this contract
                    // so the max edition field value is set to nil
                    let editionInfo = MetadataViews.Edition(name: "Avataaars", number: self.id, max: nil)
                    let editionList: [MetadataViews.Edition] = [editionInfo]
                    return MetadataViews.Editions(
                        editionList
                    )
                case Type<MetadataViews.Serial>():
                    return MetadataViews.Serial(
                        self.id
                    )
                case Type<MetadataViews.Royalties>():
                    // note: Royalties are not aware of the token being used with, so the path is not useful right now
                    // eventually the FungibleTokenSwitchboard might be an option
                    // https://github.com/onflow/flow-ft/blob/master/contracts/FungibleTokenSwitchboard.cdc
                    let cut = MetadataViews.Royalty(
                        receiver: Avataaars.account.capabilities.get<&{FungibleToken.Receiver}>(/public/somePath),
                        cut: 0.025, // 2.5% royalty
                        description: "Creator Royalty"
                    )
                    var royalties: [MetadataViews.Royalty] = [cut]
                    return MetadataViews.Royalties(royalties)
                case Type<MetadataViews.ExternalURL>():
                    // TODO: Uncomment this with your own base url!
                    // return MetadataViews.ExternalURL("YOUR_BASE_URL/".concat(self.id.toString()))
                    return nil
                case Type<MetadataViews.NFTCollectionData>():
                    return Avataaars.resolveContractView(resourceType: Type<@NFT>(), viewType: view)
                case Type<MetadataViews.NFTCollectionDisplay>():
                    return Avataaars.resolveContractView(resourceType: Type<@NFT>(), viewType: view)
                case Type<MetadataViews.Traits>():
                    let traitsView = MetadataViews.dictToTraits(dict: self.renderer.flattened, excludedNames: [])
                    return traitsView

            }
            return nil
        }

        access(all) fun createEmptyCollection(): @{NonFungibleToken.Collection} {
            return <- create Collection()
        }
    }

    /// Defines the methods that are particular to this NFT contract collection
    ///
    access(all) resource interface AvataaarsCollectionPublic: NonFungibleToken.Collection {
        access(all) fun borrowAvataaars(id: UInt64): &Avataaars.NFT? {
            post {
                (result == nil) || (result?.id == id):
                    "Cannot borrow Avataaars reference: the ID of the returned reference is incorrect"
            }
        }
    }

    /// The resource that will be holding the NFTs inside any account.
    /// In order to be able to manage NFTs any account will need to create
    /// an empty collection first
    ///
    access(all) resource Collection: AvataaarsCollectionPublic {
        // dictionary of NFT conforming tokens
        // NFT is a resource type with an `UInt64` ID field
        access(all) var ownedNFTs: @{UInt64: {NonFungibleToken.NFT}}

        init () {
            self.ownedNFTs <- {}
        }

        /// Removes an NFT from the collection and moves it to the caller
        ///
        /// @param withdrawID: The ID of the NFT that wants to be withdrawn
        /// @return The NFT resource that has been taken out of the collection
        ///
        access(NonFungibleToken.Withdraw) fun withdraw(withdrawID: UInt64): @{NonFungibleToken.NFT} {
            let token <- self.ownedNFTs.remove(key: withdrawID) ?? panic("missing NFT")

            emit Withdraw(id: token.id, from: self.owner?.address)

            return <-token
        }

        /// Adds an NFT to the collections dictionary and adds the ID to the id array
        ///
        /// @param token: The NFT resource to be included in the collection
        /// 
        access(all) fun deposit(token: @{NonFungibleToken.NFT}) {
            let token <- token as! @Avataaars.NFT

            let id: UInt64 = token.id

            // add the new token to the dictionary which removes the old one
            let oldToken <- self.ownedNFTs[id] <- token

            emit Deposit(id: id, to: self.owner?.address)

            destroy oldToken
        }

        access(all) view fun getIDs(): [UInt64] {
            return self.ownedNFTs.keys
        }

        access(all) view fun borrowNFT(_ id: UInt64): &{NonFungibleToken.NFT}? {
            return &self.ownedNFTs[id]
        }
    
        access(all) fun borrowAvataaars(id: UInt64): &Avataaars.NFT? {
            if let ref: &{NonFungibleToken.NFT} = &self.ownedNFTs[id]  {
                return ref as! &Avataaars.NFT
            }

            return nil
        }

        access(all) view fun getSupportedNFTTypes(): {Type: Bool} {
            return {
                Type<@NFT>(): true
            }
        }

        access(all) view fun isSupportedNFTType(type: Type): Bool {
            return type == Type<@NFT>()
        }

        access(all) fun createEmptyCollection(): @{NonFungibleToken.Collection} {
            return <- create Collection()
        }
    }

    /// Allows anyone to create a new empty collection
    ///
    /// @return The new Collection resource
    ///
    access(all) fun createEmptyCollection(nftType: Type): @{NonFungibleToken.Collection} {
        pre {
            nftType == Type<@NFT>(): "nftType must be nil or set to Type<Avataaars.NFT>"
        }

        return <- create Collection()
    }

    access(all) resource interface MinterPublic {
        access(all) fun mintNFT(
            recipient: &Avataaars.Collection
        )
    }

    /// Resource that an admin or something similar would own to be
    /// able to mint new NFTs
    ///
    access(all) resource NFTMinter: MinterPublic {
        /// Mints a new NFT with a new ID and deposit it in the
        /// recipients collection using their collection reference
        ///
        /// @param recipient: A capability to the collection where the new NFT will be deposited
        ///
        access(all) fun mintNFT(
            recipient: &Avataaars.Collection
        ) {
            // we want IDs to start at 1, so we'll increment first
            Avataaars.totalSupply = Avataaars.totalSupply + 1

            let admin = Avataaars.account.storage.borrow<auth(Components.Owner) &Components.Admin>(from: Components.AdminPath)!
            let renderer = admin.createRandom()

            // create a new NFT
            var newNFT <- create NFT(
                id: Avataaars.totalSupply,
                renderer: renderer
            )

            // deposit it in the recipient's account using their reference
            recipient.deposit(token: <-newNFT)

        }
    }

    access(all) struct Part {
        access(all) let name: String
        access(all) let content: String

        init(_ n: String, _ c: String) {
            self.name = n
            self.content = c
        }
    }

    /// Function that resolves a metadata view for this contract.
    ///
    /// @param view: The Type of the desired view.
    /// @return A structure representing the requested view.
    ///
    access(all) fun resolveContractView(resourceType: Type?, viewType: Type): AnyStruct? {
        switch viewType {
            case Type<MetadataViews.NFTCollectionData>():
                return MetadataViews.NFTCollectionData(
                    storagePath: Avataaars.CollectionStoragePath,
                    publicPath: Avataaars.CollectionPublicPath,
                    publicCollection: Type<&Avataaars.Collection>(),
                    publicLinkedType: Type<&Avataaars.Collection>(),
                    createEmptyCollectionFunction: (fun (): @{NonFungibleToken.Collection} {
                        return <-Avataaars.createEmptyCollection(nftType: Type<@NFT>())
                    })
                )
            case Type<MetadataViews.NFTCollectionDisplay>():
                return MetadataViews.NFTCollectionDisplay(
                        name: "Flowty Avataaars",
                        description: "This collection is used showcase the various things you can do with metadata standards on Flowty",
                        externalURL: MetadataViews.ExternalURL("https://flowty.io/"),
                        squareImage: MetadataViews.Media(
                            file: MetadataViews.HTTPFile(
                                url: self.imageBaseURL.concat("1")
                            ),
                            mediaType: "image/jpeg"
                        ),
                        bannerImage: MetadataViews.Media(
                            file: MetadataViews.HTTPFile(
                                url: "https://storage.googleapis.com/flowty-images/flowty-banner.jpeg"
                            ),
                            mediaType: "image/jpeg"
                        ),
                        socials: {
                            "twitter": MetadataViews.ExternalURL("https://twitter.com/flowty_io")
                        }
                    )
        }
        return nil
    }

    /// Function that returns all the Metadata Views implemented by a Non Fungible Token
    ///
    /// @return An array of Types defining the implemented views. This value will be used by
    ///         developers to know which parameter to pass to the resolveView() method.
    ///
    access(all) view fun getContractViews(resourceType: Type?): [Type] {
        return [
            Type<MetadataViews.NFTCollectionData>(),
            Type<MetadataViews.NFTCollectionDisplay>()
        ]
    }

    access(all) view fun borrowMinter(): &{MinterPublic} {
        return self.account.storage.borrow<&{MinterPublic}>(from: self.MinterStoragePath)!
    }

    init(imageBaseURL: String) {
        // Initialize the total supply
        self.totalSupply = 0
        self.imageBaseURL = imageBaseURL

        let identifier = "Avataaars_".concat(self.account.address.toString())

        // Set the named paths
        self.CollectionStoragePath = StoragePath(identifier: identifier)!
        self.CollectionPublicPath = PublicPath(identifier: identifier)!
        self.CollectionProviderPath = PrivatePath(identifier: identifier)!
        self.MinterStoragePath = StoragePath(identifier: identifier.concat("_Minter"))!
        self.MinterPublicPath = PublicPath(identifier: identifier.concat("_Minter"))!

        // Create a Collection resource and save it to storage
        let collection <- create Collection()
        self.account.storage.save(<-collection, to: self.CollectionStoragePath)

        // create a public capability for the collection
        self.account.capabilities.publish(
            self.account.capabilities.storage.issue<&Avataaars.Collection>(self.CollectionStoragePath),
            at: self.CollectionPublicPath
        )

        // Create a Minter resource and save it to storage
        let minter <- create NFTMinter()
        self.account.storage.save(<-minter, to: self.MinterStoragePath)
        self.account.capabilities.publish(
            self.account.capabilities.storage.issue<&{MinterPublic}>(self.MinterStoragePath),
            at: self.MinterPublicPath
        )

        emit ContractInitialized()
    }
}
 