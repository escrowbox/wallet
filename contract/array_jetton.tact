import "@stdlib/deploy";
import "./timestamped_jetton.tact";

// Контракт для работы с массивом адресов созданных контрактов
// Поддерживает создание контрактов как для native TON, так и для Jettons
// Каждый адрес кошелька имеет свой массив адресов

// Сообщение для создания контракта с поддержкой Jetton
message CreateJettonContract {
    name: String;
    targetAmount: Int as uint64;
    regularDeposite: Int as uint64;
    interval: Int as uint64;
    jettonMaster: Address?;  // null = native TON, иначе адрес мастер-контракта жетона
}

// Структура для хранения массива пользователя
struct UserArrayJ {
    count: Int as uint32;
    addresses: map<Int, Address>;  // индекс -> адрес контракта
}

// Структура для возврата из геттера
struct ArrayResultJ {
    count: Int;
    addresses: map<Int, Address>;
}

// Контракт ArrayJetton v2 (с исправленным TimestampedJetton)
contract ArrayJetton with Deployable {
    // Владелец фабрики (получает штрафы при lose)
    owner: Address;
    // Map адресов к массивам
    users: map<Address, UserArrayJ>;
    // Версия фабрики (влияет на адрес контракта)
    version: Int as uint32;

    init(owner: Address) {
        self.owner = owner;
        self.users = emptyMap();
        self.version = 2;  // v2 = fixed jetton transfer
    }

    receive() {
        // Принимаем пустое сообщение для деплоя
    }

    // Обработчик сообщения CreateJettonContract
    receive(msg: CreateJettonContract) {
        let senderAddress: Address = sender();
        let currentTime: Int = now();
        
        // Создаём StateInit для контракта TimestampedJetton
        let timestampedInit: StateInit = initOf TimestampedJetton(
            senderAddress,           // owner (создатель контракта)
            self.owner,              // factoryOwner (владелец фабрики)
            msg.name,                // name
            msg.targetAmount,        // targetAmount
            msg.regularDeposite,     // depositAmount
            msg.interval,            // interval
            currentTime,             // timestamp (createdAt)
            msg.jettonMaster         // jettonMaster (null = native TON)
        );
        
        // Вычисляем адрес контракта
        let contractAddress: Address = contractAddress(timestampedInit);
        
        // Получаем текущий массив пользователя или создаем новый
        let userArrayOpt: UserArrayJ? = self.users.get(senderAddress);
        
        let newCount: Int = 0;
        let newAddresses: map<Int, Address> = emptyMap();
        
        if (userArrayOpt != null) {
            let userArray = userArrayOpt!!;
            newAddresses = userArray.addresses;
            newCount = userArray.count;
        }
        
        // Добавляем адрес созданного контракта в map
        newAddresses.set(newCount, contractAddress);
        newCount = newCount + 1;
        
        // Сохраняем обновленный массив
        self.users.set(senderAddress, UserArrayJ{
            count: newCount,
            addresses: newAddresses
        });
        
        // Отправляем сообщение для деплоя контракта
        send(SendParameters{
            to: contractAddress,
            value: 0,
            mode: SendRemainingValue,
            bounce: false,
            body: "deploy".asComment(),
            code: timestampedInit.code,
            data: timestampedInit.data
        });
    }

    // Геттер для получения массива по адресу
    get fun getArray(userAddress: Address): ArrayResultJ {
        let userArrayOpt: UserArrayJ? = self.users.get(userAddress);
        
        if (userArrayOpt != null) {
            let userArray = userArrayOpt!!;
            return ArrayResultJ{
                count: userArray.count,
                addresses: userArray.addresses
            };
        } else {
            return ArrayResultJ{
                count: 0,
                addresses: emptyMap()
            };
        }
    }

    // Геттер для вычисления адреса контракта
    get fun getContractAddress(
        owner: Address,
        name: String,
        targetAmount: Int,
        regularDeposite: Int,
        interval: Int,
        timestamp: Int,
        jettonMaster: Address?
    ): Address {
        let timestampedInit: StateInit = initOf TimestampedJetton(
            owner,
            self.owner,
            name,
            targetAmount,
            regularDeposite,
            interval,
            timestamp,
            jettonMaster
        );
        return contractAddress(timestampedInit);
    }
}
