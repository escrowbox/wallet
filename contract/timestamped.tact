import "@stdlib/deploy";

// Structure for returning data from getter
struct ContractData {
    active: Bool;
    owner: Address;
    factoryOwner: Address;
    name: String;
    targetAmount: Int;
    depositAmount: Int;
    interval: Int;
    intervalEndTime: Int;
    totalDeposits: Int;
    createdAt: Int;
}

// Contract for deposits with time intervals
contract Timestamped with Deployable {
    // Contract active flag
    active: Bool;
    // Contract owner (creator)
    owner: Address;
    // Factory owner (receives penalties on lose)
    factoryOwner: Address;
    // Contract name
    name: String;
    // Target amount to accumulate
    targetAmount: Int as uint64;
    // Single deposit amount
    depositAmount: Int as uint64;
    // Time interval (in seconds)
    interval: Int as uint64;
    // Current interval end time
    intervalEndTime: Int as uint64;
    // Total sum of all deposits
    totalDeposits: Int as uint64;
    // Contract creation time
    createdAt: Int as uint64;

    init(owner: Address, factoryOwner: Address, name: String, targetAmount: Int, depositAmount: Int, interval: Int, timestamp: Int) {
        self.active = true;
        self.owner = owner;
        self.factoryOwner = factoryOwner;
        self.name = name;
        self.targetAmount = targetAmount;
        self.depositAmount = depositAmount;
        self.interval = interval;
        self.createdAt = timestamp;
        // Set initial deadline: current time + interval
        self.intervalEndTime = timestamp + interval;
        self.totalDeposits = 0;
    }

    receive() {
        // Accept empty message for deploy
        // On first message, init() will be called automatically with data from StateInit
    }

    // Deposit processing
    receive(msg: String) {
        if (msg == "deposit") {
            // --- AUTH ---
            require(self.active, "NOT_ACTIVE");
            require(sender() == self.owner, "NOT_OWNER");

            // --- TIME ---
            let currentTime: Int = now();

            // deposit allowed only within its interval
            require(
                currentTime > self.intervalEndTime - self.interval,
                "TOO_EARLY"
            );

            // --- VALUE ---
            // Use context().value to get exact incoming message amount
            let value: Int = context().value;
            require(value >= self.depositAmount, "WRONG_AMOUNT");

            // --- STATE UPDATE ---
            self.totalDeposits = self.totalDeposits + value;

            // --- SUCCESS PATH ---
            if (self.totalDeposits >= self.targetAmount) {
                // close contract BEFORE sending
                self.active = false;

                // send entire contract balance to owner
                send(SendParameters{
                    to: self.owner,
                    value: 0,
                    mode: SendRemainingBalance,  // Send entire contract balance
                    bounce: false
                });
            } else {
                // move deadline forward
                self.intervalEndTime = self.intervalEndTime + self.interval;
            }
        } else if (msg == "lose") {
            require(self.active, "NOT_ACTIVE");

            let currentTime: Int = now();
            require(currentTime > self.intervalEndTime, "NOT_LATE");
            require(self.totalDeposits < self.targetAmount, "ALREADY_COMPLETED");

            self.active = false;

            // Send penalty to factory owner
            send(SendParameters{
                to: self.factoryOwner,
                value: 0,
                mode: SendRemainingBalance,  // Send entire contract balance
                bounce: false
            });
        }
    }

    // Getter for retrieving all contract data
    get fun getContractData(): ContractData {
        return ContractData{
            active: self.active,
            owner: self.owner,
            factoryOwner: self.factoryOwner,
            name: self.name,
            targetAmount: self.targetAmount,
            depositAmount: self.depositAmount,
            interval: self.interval,
            intervalEndTime: self.intervalEndTime,
            totalDeposits: self.totalDeposits,
            createdAt: self.createdAt
        };
    }
}
