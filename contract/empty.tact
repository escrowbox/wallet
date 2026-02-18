import "@stdlib/deploy";

// Простой пустой контракт без функций и переменных
contract Empty with Deployable {
    init() {
        // Пустая инициализация
    }

    receive() {
        // Принимаем пустое сообщение для деплоя
    }
}
