import "@stdlib/deploy";
import "./timestamped.tact";

// Contract for working with an array of created contract addresses
// When AddOne is called, a Timestamped contract (with creation time getter) is created and its address is added to the array
// Each wallet address has its own array of addresses

message CreateContract {
    // Message for creating a contract with parameters
    name: String;
    targetAmount: Int as uint64;
    regularDeposite: Int as uint64;
    interval: Int as uint64;
}

// Structure for storing user's array
struct UserArray {
    count: Int as uint32;
    addresses: map<Int, Address>;  // index -> contract address (no limit on quantity)
}

// Structure for returning from getter
struct ArrayResult {
    count: Int;
    addresses: map<Int, Address>;
}

// Array Contract
contract Array with Deployable {
    // Factory owner (receives penalties on lose)
    owner: Address;
    // Map of addresses to arrays
    users: map<Address, UserArray>;

    init(owner: Address) {
        self.owner = owner;
        self.users = emptyMap();
    }

    // Empty message handler for deploy (Deployable trait)
    receive() {
        // Accept empty message for deploy
    }

    // CreateContract message handler
    receive(msg: CreateContract) {
        // Get sender address (wallet address) - will be contract owner
        let senderAddress: Address = sender();
        
        // Get factory address (this contract)
        let factoryAddress: Address = myAddress();
        
        // Get current time (Unix timestamp in seconds)
        let currentTime: Int = now();
        
        // Use initOf to generate correct StateInit
        // initOf automatically creates StateInit with correct data format,
        // which matches the expectations of the Tact compiler
        let timestampedInit: StateInit = initOf Timestamped(
            senderAddress,           // owner (contract creator)
            self.owner,              // factoryOwner (factory owner - receives penalties)
            msg.name,                // name (contract name)
            msg.targetAmount,        // targetAmount
            msg.regularDeposite,     // depositAmount
            msg.interval,            // interval
            currentTime              // timestamp (createdAt)
        );
        
        // Calculate Timestamped contract address
        let timestampedContractAddress: Address = contractAddress(timestampedInit);
        
        // Get current user array or create new one
        let userArrayOpt: UserArray? = self.users.get(senderAddress);
        
        let newCount: Int = 0;
        let newAddresses: map<Int, Address> = emptyMap();
        
        if (userArrayOpt != null) {
            let userArray = userArrayOpt!!;
            // Use existing addresses map
            newAddresses = userArray.addresses;
            newCount = userArray.count;
        }
        
        // Add created contract address to map at current index
        newAddresses.set(newCount, timestampedContractAddress);
        newCount = newCount + 1;
        
        // Save updated array
        self.users.set(senderAddress, UserArray{
            count: newCount,
            addresses: newAddresses
        });
        
        // Send message to deploy Timestamped contract
        // Use SendRemainingValue to pass all remaining funds
        // This ensures there's enough money for deployment
        send(SendParameters{
            to: timestampedContractAddress,
            value: 0,                        // will be overridden by mode
            mode: SendRemainingValue,        // send all remaining funds (minus gas)
            bounce: false,
            body: "deploy".asComment(),      // we must piggyback the deployment on another message
            code: timestampedInit.code,      // attaching the StateInit will cause the message to deploy
            data: timestampedInit.data
        });
    }

    // Getter for retrieving array by address
    get fun getArray(userAddress: Address): ArrayResult {
        let userArrayOpt: UserArray? = self.users.get(userAddress);
        
        if (userArrayOpt != null) {
            let userArray = userArrayOpt!!;
            return ArrayResult{
                count: userArray.count,
                addresses: userArray.addresses
            };
        } else {
            // If array not found, return empty
            return ArrayResult{
                count: 0,
                addresses: emptyMap()
            };
        }
    }
}
