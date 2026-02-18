import "@stdlib/deploy";
import "./jetton_messages.tact";

// Структура для возврата данных из геттера
struct JettonContractData {
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
    // Jetton-специфичные поля
    jettonMaster: Address?;           // Адрес мастер-контракта жетона (null = native TON)
    jettonWallet: Address?;           // Адрес jetton wallet этого контракта
    isJetton: Bool;                   // Флаг: true = jetton, false = native TON
}

// Контракт для депозитов с временными интервалами и поддержкой Jettons
contract TimestampedJetton with Deployable {
    // Флаг активности контракта
    active: Bool;
    // Владелец контракта (создатель)
    owner: Address;
    // Владелец фабрики (получает штрафы при lose)
    factoryOwner: Address;
    // Название контракта
    name: String;
    // Целевая сумма для накопления
    targetAmount: Int as uint64;
    // Сумма одного депозита
    depositAmount: Int as uint64;
    // Интервал времени (в секундах)
    interval: Int as uint64;
    // Время окончания текущего интервала
    intervalEndTime: Int as uint64;
    // Общая сумма всех депозитов
    totalDeposits: Int as uint64;
    // Время создания контракта
    createdAt: Int as uint64;
    
    // === Jetton-специфичные поля ===
    // Адрес мастер-контракта жетона (null для native TON)
    jettonMaster: Address?;
    // Адрес jetton wallet этого контракта (устанавливается после деплоя)
    jettonWallet: Address?;
    // Флаг: используем jetton или native TON
    isJetton: Bool;

    init(
        owner: Address, 
        factoryOwner: Address, 
        name: String, 
        targetAmount: Int, 
        depositAmount: Int, 
        interval: Int, 
        timestamp: Int,
        jettonMaster: Address?  // null = native TON
    ) {
        self.active = true;
        self.owner = owner;
        self.factoryOwner = factoryOwner;
        self.name = name;
        self.targetAmount = targetAmount;
        self.depositAmount = depositAmount;
        self.interval = interval;
        self.createdAt = timestamp;
        self.intervalEndTime = timestamp + interval;
        self.totalDeposits = 0;
        
        // Jetton настройки
        self.jettonMaster = jettonMaster;
        self.jettonWallet = null;  // Будет установлен позже через SetJettonWallet
        self.isJetton = jettonMaster != null;
    }

    receive() {
        // Принимаем пустое сообщение для деплоя
    }

    // Установка адреса jetton wallet (вызывается owner после деплоя)
    receive(msg: SetJettonWallet) {
        require(sender() == self.owner, "NOT_OWNER");
        require(self.isJetton, "NOT_JETTON_MODE");
        require(self.jettonWallet == null, "ALREADY_SET");
        
        self.jettonWallet = msg.jettonWalletAddress;
    }

    // Обработка депозита в native TON
    receive(msg: String) {
        if (msg == "deposit") {
            // Для native TON депозита
            require(!self.isJetton, "USE_JETTON_DEPOSIT");
            self._processDeposit(context().value);
        } else if (msg == "lose") {
            self._processLose();
        }
    }

    // Обработка депозита в Jettons (transfer_notification от jetton wallet)
    receive(msg: JettonTransferNotification) {
        // --- AUTH (критические проверки - откат) ---
        require(self.isJetton, "NOT_JETTON_MODE");
        
        // Проверяем что сообщение пришло от нашего jetton wallet
        let jettonWallet: Address = self.jettonWallet!!;
        require(sender() == jettonWallet, "INVALID_JETTON_WALLET");
        
        // Проверяем что отправитель жетонов - владелец контракта
        require(msg.sender == self.owner, "NOT_OWNER");
        
        // --- SOFT CHECKS (возврат жетонов вместо отката) ---
        let currentTime: Int = now();
        
        // Контракт неактивен - возвращаем жетоны
        if (!self.active) {
            self._sendJettonsTo(msg.sender, msg.amount);
            return;
        }
        
        // Слишком рано для депозита - возвращаем жетоны
        if (currentTime <= self.intervalEndTime - self.interval) {
            self._sendJettonsTo(msg.sender, msg.amount);
            return;
        }
        
        // Неверная сумма депозита - возвращаем жетоны
        if (msg.amount < self.depositAmount) {
            self._sendJettonsTo(msg.sender, msg.amount);
            return;
        }
        
        // Обрабатываем депозит (все проверки пройдены)
        self._processJettonDeposit(msg.amount);
    }

    // Внутренняя функция обработки депозита (для native TON)
    fun _processDeposit(amount: Int) {
        // --- AUTH ---
        require(self.active, "NOT_ACTIVE");

        // --- TIME ---
        let currentTime: Int = now();

        // Депозит разрешён только в своём интервале
        require(
            currentTime > self.intervalEndTime - self.interval,
            "TOO_EARLY"
        );

        // --- VALUE ---
        require(amount >= self.depositAmount, "WRONG_AMOUNT");

        // --- STATE UPDATE ---
        self.totalDeposits = self.totalDeposits + amount;

        // --- SUCCESS PATH ---
        if (self.totalDeposits >= self.targetAmount) {
            // Закрываем контракт ПЕРЕД отправкой
            self.active = false;

            // Отправляем накопления владельцу (native TON)
            send(SendParameters{
                to: self.owner,
                value: 0,
                mode: SendRemainingBalance,
                bounce: false
            });
        } else {
            // Переносим дедлайн
            self.intervalEndTime = self.intervalEndTime + self.interval;
        }
    }

    // Внутренняя функция обработки jetton депозита (проверки уже выполнены)
    fun _processJettonDeposit(amount: Int) {
        // --- STATE UPDATE ---
        self.totalDeposits = self.totalDeposits + amount;

        // --- SUCCESS PATH ---
        if (self.totalDeposits >= self.targetAmount) {
            // Закрываем контракт ПЕРЕД отправкой
            self.active = false;

            // Отправляем накопления владельцу
            self._sendJettonsTo(self.owner, self.totalDeposits);
        } else {
            // Переносим дедлайн
            self.intervalEndTime = self.intervalEndTime + self.interval;
        }
    }

    // Внутренняя функция обработки проигрыша
    fun _processLose() {
        require(self.active, "NOT_ACTIVE");

        let currentTime: Int = now();
        require(currentTime > self.intervalEndTime, "NOT_LATE");
        require(self.totalDeposits < self.targetAmount, "ALREADY_COMPLETED");

        self.active = false;

        // Отправляем штраф владельцу фабрики
        if (self.isJetton) {
            self._sendJettonsTo(self.factoryOwner, self.totalDeposits);
        } else {
            send(SendParameters{
                to: self.factoryOwner,
                value: 0,
                mode: SendRemainingBalance,
                bounce: false
            });
        }
    }

    // Отправка жетонов на указанный адрес
    // Формируем JettonTransfer вручную для совместимости со стандартным Jetton Wallet
    fun _sendJettonsTo(destination: Address, amount: Int) {
        let jettonWallet: Address = self.jettonWallet!!;
        
        // Формируем тело JettonTransfer вручную (opcode 0x0f8a7ea5)
        // Стандартный формат: opcode, query_id, amount, destination, response_destination, 
        //                     custom_payload (Maybe Cell), forward_ton_amount, forward_payload (Either Cell | Slice)
        let body: Cell = beginCell()
            .storeUint(0x0f8a7ea5, 32)           // opcode transfer
            .storeUint(0, 64)                     // query_id
            .storeCoins(amount)                   // amount
            .storeAddress(destination)            // destination
            .storeAddress(destination)            // response_destination
            .storeUint(0, 1)                      // custom_payload = null (0 bit)
            .storeCoins(ton("0.01"))             // forward_ton_amount
            .storeUint(0, 1)                      // either bit = 0 (inline payload, пустой)
            .endCell();
        
        send(SendParameters{
            to: jettonWallet,
            value: ton("0.05"),  // Газ для отправки жетонов
            mode: SendPayGasSeparately,
            bounce: true,
            body: body
        });

        // Отправляем оставшиеся TON (для газа) тоже владельцу
        send(SendParameters{
            to: destination,
            value: 0,
            mode: SendRemainingBalance,
            bounce: false
        });
    }

    // Аварийный вывод жетонов (только owner)
    receive(msg: WithdrawJettons) {
        require(sender() == self.owner, "NOT_OWNER");
        require(self.isJetton, "NOT_JETTON_MODE");
        require(!self.active, "STILL_ACTIVE");
        
        self._sendJettonsTo(msg.destination, msg.amount);
    }

    // Геттер для получения всех данных контракта
    get fun getContractData(): JettonContractData {
        return JettonContractData{
            active: self.active,
            owner: self.owner,
            factoryOwner: self.factoryOwner,
            name: self.name,
            targetAmount: self.targetAmount,
            depositAmount: self.depositAmount,
            interval: self.interval,
            intervalEndTime: self.intervalEndTime,
            totalDeposits: self.totalDeposits,
            createdAt: self.createdAt,
            jettonMaster: self.jettonMaster,
            jettonWallet: self.jettonWallet,
            isJetton: self.isJetton
        };
    }

    // Геттер для проверки готовности к депозитам
    get fun isReady(): Bool {
        if (self.isJetton) {
            return self.jettonWallet != null;
        }
        return true;  // Native TON всегда готов
    }
}
