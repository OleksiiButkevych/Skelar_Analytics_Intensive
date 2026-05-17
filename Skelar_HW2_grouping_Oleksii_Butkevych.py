import pandas as pd

# 1. Завантажуємо файли
spend = pd.read_csv('spend.csv')
users = pd.read_csv('users.csv')

# 2. Агрегуємо юзерів до рівня: Дата, Канал, Гео ТА ПРИСТРІЙ (device_os)
# Тепер ми не втрачаємо інформацію про ОС
users_agg = users.groupby(['registration_date', 'channel', 'geo', 'device_os']).agg({
    'id_user': 'count',      # Кількість реєстрацій
    'is_payer': 'sum',       # Кількість платників
    'revenue_7d': 'sum',     # Виручка за 7 днів
    'revenue_90d': 'sum'     # Виручка за 90 днів
}).reset_index()

# Перейменовуємо колонки для зручності та джойну
users_agg.rename(columns={
    'registration_date': 'date',
    'id_user': 'users_count',
    'is_payer': 'payers_count'
}, inplace=True)

# 3. Об'єднуємо таблиці (Left Join)
# Ми приєднуємо витрати до юзерів.
# Оскільки витрати у spend.csv існують лише на рівні (date, channel, geo),
# Tableau буде бачити загальний spend для всіх пристроїв у межах цієї групи.
final_table = pd.merge(users_agg, spend, on=['date', 'channel', 'geo'], how='left')

# 4. Обробка витрат (Важливо!)
# Оскільки spend повторюється для кожного пристрою, у Tableau при розрахунку загального Spend
# треба буде використовувати AVG або MIN, щоб не отримати роздуті цифри.
# Але для Sheet 1 та Sheet 2 (де немає device_os) все буде рахуватися коректно.
final_table = final_table.fillna(0)

# 5. Зберігаємо фінальний файл
final_table.to_csv('marketing_performance_with_os.csv', index=False)

print("Готово! Тепер у файлі 'marketing_performance_with_os.csv' є колонка device_os.")