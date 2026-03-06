try:
    import paramiko
    print("paramiko OK version:", paramiko.__version__)
except ImportError as e:
    print("paramiko not available:", e)
