export FILTER_BRANCH_SQUELCH_WARNING=1

git filter-branch -f  --env-filter '
WRONG_EMAIL="h.naitboubker@4digital.ma"
NEW_NAME="hamza-nb"
NEW_EMAIL="hamzanb8@gmail.com"


     export GIT_AUTHOR_NAME="$NEW_NAME"
     export GIT_AUTHOR_EMAIL="$NEW_EMAIL"

' -- --all

export FILTER_BRANCH_SQUELCH_WARNING=0

# git push -f origin $1
