import sys


def hello_world():
    print("Hello, World!")


def health_check():
    print("Health check: OK")
    return True


if __name__ == "__main__":
    hello_world()
    if health_check():
        sys.exit(0)
    else:
        sys.exit(1)
