import asyncio
import logging
import mysql.connector
from aiogram import Bot, Dispatcher, types
from aiogram.filters import Command
from aiogram.types import InlineKeyboardButton
from aiogram.utils.keyboard import InlineKeyboardBuilder
import random
import string
import requests
import base64
import threading
from datetime import timedelta
from dotenv import load_dotenv
import os

# Load environment variables from .env
load_dotenv()

# Enable logging
logging.basicConfig(level=logging.INFO)

# Bot and GitHub settings from .env
BOT_TOKEN = os.getenv('BOT_TOKEN')
GITHUB_TOKEN = os.getenv('GITHUB_TOKEN')
OWNER = os.getenv('GITHUB_OWNER')
REPO = os.getenv('GITHUB_REPO')
FILE_PATH = os.getenv('GITHUB_FILE_PATH')
BOT_LINK = os.getenv('BOT_LINK')  # Added BOT_LINK for keys.lua

# Initialize bot and dispatcher
bot = Bot(token=BOT_TOKEN)
dp = Dispatcher()

# MySQL Database Setup from .env
db_config = {
    'host': os.getenv('DB_HOST'),
    'user': os.getenv('DB_USER'),
    'password': os.getenv('DB_PASSWORD'),
    'database': os.getenv('DB_DATABASE')
}

def get_db_connection():
    return mysql.connector.connect(**db_config)

# Function to get all channel usernames from DB (parse from full links if needed)
def get_channels():
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute('SELECT username FROM channels')
        raw_channels = [row[0] for row in cursor.fetchall()]
        cursor.close()
        conn.close()
        # Parse to get clean username (e.g., 'roblox' from 'https://t.me/roblox')
        channels = []
        for ch in raw_channels:
            if ch.startswith('https://t.me/'):
                ch = ch.replace('https://t.me/', '').strip('/')
            channels.append(ch)
        return channels
    except Exception as e:
        print(f"DB channels fetch error: {e}")
        return []

# Function to generate a random key
def generate_key(length=12):
    characters = string.ascii_letters + string.digits
    return ''.join(random.choice(characters) for _ in range(length))

# Function to insert new key into DB (with used=0)
def insert_key(key):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute('INSERT IGNORE INTO `keys` (`key`, `used`) VALUES (%s, 0)', (key,))
        conn.commit()
        cursor.close()
        conn.close()
        print(f"New key inserted: {key} with used=0")
    except Exception as e:
        print(f"DB insert error: {e}")

# Function to increment used (request count) for a key
def increment_request_count(key):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute('UPDATE `keys` SET `used` = `used` + 1 WHERE `key` = %s', (key,))
        conn.commit()
        if cursor.rowcount == 0:
            print(f"Warning: Key {key} not found in DB for update.")
        cursor.close()
        conn.close()
        print(f"Used count incremented for key: {key}")
    except Exception as e:
        print(f"DB update error: {e}")

# Function to update GitHub file with new key and bot link
def update_github_key(key):
    url = f"https://api.github.com/repos/{OWNER}/{REPO}/contents/{FILE_PATH}"
    headers = {
        'Authorization': f'token {GITHUB_TOKEN}',
        'Accept': 'application/vnd.github.v3+json'
    }
    content = f'return {{\n    key = "{key}",\n    botLink = "{BOT_LINK}"\n}}'
    encoded_content = base64.b64encode(content.encode('utf-8')).decode('utf-8')

    # Get SHA of current file
    response = requests.get(url, headers=headers)
    if response.status_code == 200:
        sha = response.json()['sha']
    else:
        sha = None  # If file not exists, create new
        print(f"GitHub GET response: {response.status_code} - {response.text}")

    data = {
        'message': 'Update current key and bot link',
        'content': encoded_content,
        'sha': sha if sha else None
    }
    response = requests.put(url, headers=headers, json=data)
    if response.status_code == 200 or response.status_code == 201:
        print(f"GitHub file updated with key: {key} and botLink: {BOT_LINK}")
    else:
        print(f"Error updating GitHub: {response.status_code} - {response.text}")

# Function to get CURRENT key from GitHub (for /getkey)
def get_current_key():
    url = f"https://api.github.com/repos/{OWNER}/{REPO}/contents/{FILE_PATH}"
    headers = {
        'Authorization': f'token {GITHUB_TOKEN}',
        'Accept': 'application/vnd.github.v3+json'
    }
    response = requests.get(url, headers=headers)
    if response.status_code == 200:
        encoded_content = response.json()['content']
        content = base64.b64decode(encoded_content).decode('utf-8')
        # Parse key from 'return {key = "key", botLink = "link"}' format
        if 'return {' in content:
            key = content.split('key = "')[1].split('"')[0]  # Extract key
            print(f"Current key fetched: {key}")
            return key
        else:
            raise Exception("Invalid content format in keys.lua")
    else:
        raise Exception(f"Failed to fetch file: {response.status_code} - {response.text}")

# Background task to change key every 1 day (for prod; change to 3 days if needed)
async def change_key_periodically():
    while True:
        key = generate_key()
        insert_key(key)  # Insert new key with used=0
        update_github_key(key)
        print(f"Background key changed to: {key}")
        # For prod: 1 day
        await asyncio.sleep(timedelta(days=1).total_seconds())
        # For test: 5 min (300 sec) - commented out
        # await asyncio.sleep(300)
        # For prod (3 days): await asyncio.sleep(timedelta(days=3).total_seconds())  # 259200 sec

@dp.message(Command("start"))
async def start_handler(message: types.Message):
    await message.reply(
        'Привет! 🇷🇺\n'
        'Используй /getkey, чтобы получить ключ для активации key system.\n\n'
        'Hi! 🇬🇧\n'
        'Use /getkey to get the key to activate the key system.'
    )

@dp.message(Command("getkey"))
async def getkey_handler(message: types.Message):
    channels = get_channels()
    if not channels:
        await message.reply('Нет настроенных каналов. Обратитесь к админу.')
        return

    builder = InlineKeyboardBuilder()
    for ch in channels:
        builder.row(InlineKeyboardButton(text="Подписаться", url=f"https://t.me/{ch}"))
    builder.row(InlineKeyboardButton(text="Проверить", callback_data="check_subscription"))

    await message.reply(
        'Подпишись и получи ключ\n'
        'Subscribe and get the key',
        reply_markup=builder.as_markup()
    )

@dp.callback_query(lambda c: c.data == 'check_subscription')
async def check_subscription(callback: types.CallbackQuery):
    channels = get_channels()
    if not channels:
        await callback.answer('Нет настроенных каналов.')
        return

    user_id = callback.from_user.id
    subscribed = True
    for ch in channels:
        chat_id = f'@{ch}'
        try:
            member = await bot.get_chat_member(chat_id, user_id)
            if member.status not in ['member', 'creator', 'administrator']:
                subscribed = False
                break
        except Exception as e:
            print(f"Error checking subscription for {ch}: {e}")
            subscribed = False
            break

    if subscribed:
        try:
            key = get_current_key()
            increment_request_count(key)
            await callback.message.reply(
                f'**Ваш текущий ключ: **`{key}`**\n'
                f'**Your current key: **`{key}`**\n\n'
                f'**🇷🇺 Скопируй и вставь его в кей систему**\n\n'
                f'**🇬🇧 Copy and paste it into your key system**',
                parse_mode='MarkdownV2'
            )
            await callback.answer('Ключ выдан!')
        except Exception as e:
            await callback.answer(f'Ошибка: {str(e)}')
    else:
        await callback.answer('Вы не подписаны на все каналы!')

async def main():
    # Start key changer in background
    asyncio.create_task(change_key_periodically())
    await dp.start_polling(bot)

if __name__ == '__main__':
    asyncio.run(main())
