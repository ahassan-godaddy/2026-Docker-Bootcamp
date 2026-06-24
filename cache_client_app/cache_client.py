import fire
from valkey import Valkey
import os

CACHE_HOST = os.environ.get("CACHE_HOST", "cache")

data = {}


def store_data():
    key = input("What should we call this data?\n")
    value = input("What is the data?\n")

    c = get_cache_client()
    c.set(key, value)
    print("The data has been stored in the cache")


def get_data(key=None, *a, **k):
    key = key or input("What was name of the data?\n")
    val = None
    if key:
        c = get_cache_client()
        val = c.get(key)
        if val:
            print("The data is in the cache!")
            val = val.decode()
        else:
            val = "Not Found"
    return f"{key=}\n{val=}"


def get_cache_client():
    return Valkey(host=CACHE_HOST)


def hello_world():
    print("Oh hai")


def check_cache():
    c = get_cache_client()
    if c:
        c.set(name="test", value="test")
        c.get("test")
        c.delete("test")
        print("True")
        exit(0)

    exit(1)


if __name__ == '__main__':
    fire.Fire(dict(
        store_data=store_data,
        get_data=get_data,
        check_cache=check_cache,
        hello_world=hello_world
    ))
