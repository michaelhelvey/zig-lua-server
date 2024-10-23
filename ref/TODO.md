Todays goal: refactoring zig lua server into unit testable modules instead of giant functions

---

- [ ] refactor lua code as a struct to manage the LuaState argument
- [ ] create a request type that manages the serialization/deserialization to lua
- [ ] create e response type that does the same thing
- [ ] create a query parameter parser
- [ ] figure out how the respondStreaming() API is supposed to work
