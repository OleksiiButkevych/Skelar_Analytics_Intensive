import pandas as pd

# 1. Завантажуємо файли
spend = pd.read_csv('spend.csv')
users = pd.read_csv('users.csv')

# Приводимо дати до єдиного формату datetime
spend['date'] = pd.to_datetime(spend['date'])
users['registration_date'] = pd.to_datetime(users['registration_date'])

# 2. ДЕКУМУЛЯЦІЯ кумулятивних витрат
# Сортуємо за КАНАЛОМ, ГЕО та ДАТОЮ (оскільки ad_id немає в описі)
spend = spend.sort_values(by=['channel', 'geo', 'date'])

# Рахуємо чисті витрати за день для кожної комбінації канал+гео
# fill_value=spend['spend'] залишає початкові витрати для першого дня
spend['daily_spend'] = spend.groupby(['channel', 'geo'])['spend'].diff().fillna(spend['spend'])

# Прибираємо можливі мінуси (аномалії даних)
spend['daily_spend'] = spend['daily_spend'].clip(lower=0)

# 3. Агрегуємо чисті щоденні витрати (про всяк випадок, якщо є дублі рядків)
spend_daily_agg = spend.groupby(['date', 'channel', 'geo'])['daily_spend'].sum().reset_index()

# 4. Агрегуємо юзерів до рівня: Дата, Канал, Гео, Пристрій (device_os)
users_agg = users.groupby(['registration_date', 'channel', 'geo', 'device_os']).agg({
    'id_user': 'count',
    'is_payer': 'sum',
    'revenue_7d': 'sum',
    'revenue_90d': 'sum'
}).reset_index()

# Перейменовуємо колонки юзерів
users_agg.rename(columns={
    'registration_date': 'date',
    'id_user': 'users_count',
    'is_payer': 'payers_count'
}, inplace=True)

# 5. Розрахунок частки кожної ОС для пропорційного розподілу витрат
total_users_per_group = users_agg.groupby(['date', 'channel', 'geo'])['users_count'].transform('sum')
users_agg['os_share'] = users_agg['users_count'] / total_users_per_group

# 6. Об'єднуємо щоденні витрати з агрегованими юзерами (Left Join)
final_table = pd.merge(users_agg, spend_daily_agg, on=['date', 'channel', 'geo'], how='left')
final_table['daily_spend'] = final_table['daily_spend'].fillna(0)

# 7. Розподіляємо денні витрати відповідно до частки кожної ОС
final_table['spend'] = final_table['daily_spend'] * final_table['os_share']

# Прибираємо тимчасові колонки
final_table.drop(columns=['os_share', 'daily_spend'], inplace=True)

# Повертаємо формат дати назад у YYYY-MM-DD
final_table['date'] = final_table['date'].dt.strftime('%Y-%m-%d')

# 8. Зберігаємо фінальний чистий файл
final_table.to_csv('marketing_performance_clean_os.csv', index=False)

print("Готово! Кумулятив пораховано по розрізу channel+geo, дані успішно декумульовано та розподілено.")
