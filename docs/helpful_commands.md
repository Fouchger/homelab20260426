# Helpful Commands



## Error: /usr/bin/env: bad interpreter: Text file busy
```
FILE='scripts/banner/banner.sh'
FOLDER='/root/Github/HomeLab20260426'

cd '$FOLDER'

# Check who has the file open
fuser -v '$FILE' || true

# Fix line endings and permissions
sed -i 's/\r$//' '$FILE'
chmod +x '$FILE'

# Run it via bash first
bash '$FILE'
```

## 