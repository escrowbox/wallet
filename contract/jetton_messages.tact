// Стандартные сообщения для работы с Jetton (TEP-74)

// Сообщение transfer_notification от jetton wallet к получателю
// opcode: 0x7362d09c
message(0x7362d09c) JettonTransferNotification {
    queryId: Int as uint64;           // ID запроса
    amount: Int as coins;              // Количество переведённых жетонов
    sender: Address;                   // Адрес предыдущего владельца (кто отправил)
    forwardPayload: Slice as remaining; // Дополнительные данные
}

// Сообщение transfer для отправки жетонов (отправляется на jetton wallet)
// opcode: 0x0f8a7ea5
message(0x0f8a7ea5) JettonTransfer {
    queryId: Int as uint64;           // ID запроса
    amount: Int as coins;              // Количество жетонов для отправки
    destination: Address;              // Адрес получателя (обычный кошелёк)
    responseDestination: Address;      // Куда отправить excess TON
    customPayload: Cell?;              // Кастомные данные (опционально)
    forwardTonAmount: Int as coins;    // Количество TON для пересылки получателю
    forwardPayload: Slice as remaining; // Данные для пересылки получателю
}

// Сообщение для установки адреса jetton wallet
message SetJettonWallet {
    jettonWalletAddress: Address;
}

// Сообщение для вывода средств владельцем (для аварийных ситуаций)
message WithdrawJettons {
    amount: Int as coins;
    destination: Address;
}
