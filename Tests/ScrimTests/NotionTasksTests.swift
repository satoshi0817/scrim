import XCTest
@testable import ScrimCore

final class NotionTasksTests: XCTestCase {
    private let statusSchema = NotionDataSourceSchema(id: "ds-1", title: "プロジェクト", properties: [
        NotionProperty(id: "title", name: "名前", kind: .title),
        NotionProperty(id: "%3AUPp", name: "ステータス", kind: .status,
                       options: [.init(id: "o1", name: "未着手"), .init(id: "o2", name: "進行中"), .init(id: "o3", name: "完了"), .init(id: "o4", name: "中止")],
                       groups: [.init(id: "g1", name: "To-do", optionIDs: ["o1"]), .init(id: "g2", name: "In progress", optionIDs: ["o2"]),
                                .init(id: "g3", name: "Complete", optionIDs: ["o3", "o4"])]),
        NotionProperty(id: "d%2Fe", name: "期限", kind: .date),
        NotionProperty(id: "tag", name: "タグ", kind: .other("multi_select")),
    ])
    private func body(_ request: NotionRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
    }

    func testMappingRoundTripsThroughPanelURLWithEncodedPropertyIDs() {
        let mapping = NotionTaskMapping(dataSourceID: "ds-1", name: "仕事 & 個人", titleProperty: "title",
                                        completion: .status(property: "%3AUPp", done: "o3"), dueProperty: "d%2Fe")
        let spec = WidgetSpec(kind: .notionTasks, notionTasks: mapping)
        XCTAssertEqual(WidgetSpec(url: spec.url)?.notionTasks, mapping)
        let checkbox = NotionTaskMapping(dataSourceID: "ds-2", name: "", titleProperty: "title", completion: .checkbox(property: "c"))
        XCTAssertEqual(WidgetSpec(url: WidgetSpec(kind: .notionTasks, notionTasks: checkbox).url)?.notionTasks, checkbox)
        XCTAssertNil(WidgetSpec(url: WidgetSpec(kind: .notionTasks).url)?.notionTasks)
        XCTAssertNil(WidgetSpec(kind: .clock, notionTasks: mapping).notionTasks)
        XCTAssertNil(NotionTaskMapping(queryItems: [URLQueryItem(name: "source", value: "x"), URLQueryItem(name: "titleProp", value: "t"),
                                                    URLQueryItem(name: "doneProp", value: "s"), URLQueryItem(name: "doneType", value: "status")]))
    }

    func testDefaultMappingPicksCompleteGroupAndFirstDate() {
        let mapping = statusSchema.defaultMapping()
        XCTAssertEqual(mapping?.titleProperty, "title")
        XCTAssertEqual(mapping?.completion, .status(property: "%3AUPp", done: "o3"))
        XCTAssertEqual(mapping?.dueProperty, "d%2Fe")
        XCTAssertEqual(mapping?.name, "プロジェクト")
        XCTAssertEqual(mapping.map(statusSchema.completeOptionIDs), ["o3", "o4"])
        let noCompletion = NotionDataSourceSchema(id: "x", title: "", properties: [NotionProperty(id: "title", name: "名前", kind: .title)])
        XCTAssertNil(noCompletion.defaultMapping())
    }

    func testMappingProblemsNameTheMissingColumn() throws {
        let mapping = try XCTUnwrap(statusSchema.defaultMapping())
        XCTAssertNil(statusSchema.mappingProblem(mapping))
        var missingDue = mapping; missingDue.dueProperty = "gone"
        XCTAssertNotNil(statusSchema.mappingProblem(missingDue))
        var wrongOption = mapping; wrongOption.completion = .status(property: "%3AUPp", done: "gone")
        XCTAssertNotNil(statusSchema.mappingProblem(wrongOption))
        var wrongType = mapping; wrongType.completion = .checkbox(property: "%3AUPp")
        XCTAssertNotNil(statusSchema.mappingProblem(wrongType))
    }

    func testOpenTaskQueryExcludesEveryCompleteStatus() throws {
        let mapping = try XCTUnwrap(statusSchema.defaultMapping())
        let request = NotionRequests.openTasks(mapping, schema: statusSchema, cursor: "next")
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "v1/data_sources/ds-1/query")
        let json = try body(request)
        let clauses = try XCTUnwrap((json["filter"] as? [String: Any])?["and"] as? [[String: Any]])
        XCTAssertEqual(clauses.compactMap { ($0["status"] as? [String: String])?["does_not_equal"] }, ["完了", "中止"])
        XCTAssertEqual(json["start_cursor"] as? String, "next")
        let checkbox = NotionTaskMapping(dataSourceID: "ds-2", name: "", titleProperty: "title", completion: .checkbox(property: "c"))
        let filter = try XCTUnwrap(try body(NotionRequests.openTasks(checkbox, schema: statusSchema))["filter"] as? [String: Any])
        XCTAssertEqual(filter["property"] as? String, "c")
        XCTAssertEqual((filter["checkbox"] as? [String: Bool])?["equals"], false)
    }

    func testWritesUsePropertyIDsAndOnlyTouchChangedFields() throws {
        let mapping = try XCTUnwrap(statusSchema.defaultMapping())
        let create = try body(NotionRequests.createTask(mapping, title: "見積もり", due: NotionDate(start: "2026-11-30")))
        XCTAssertEqual((create["parent"] as? [String: String])?["data_source_id"], "ds-1")
        let properties = try XCTUnwrap(create["properties"] as? [String: Any])
        XCTAssertEqual(Set(properties.keys), ["title", "d%2Fe"])
        XCTAssertEqual(((properties["d%2Fe"] as? [String: Any])?["date"] as? [String: String])?["start"], "2026-11-30")

        let complete = try XCTUnwrap(try body(NotionRequests.updateTask("p1", mapping, completed: true))["properties"] as? [String: Any])
        XCTAssertEqual(Set(complete.keys), ["%3AUPp"])
        XCTAssertEqual(((complete["%3AUPp"] as? [String: Any])?["status"] as? [String: String])?["id"], "o3")
        let undo = try XCTUnwrap(try body(NotionRequests.updateTask("p1", mapping, completed: false, restoreStatusOptionID: "o2"))["properties"] as? [String: Any])
        XCTAssertEqual(((undo["%3AUPp"] as? [String: Any])?["status"] as? [String: String])?["id"], "o2")
        let clear = try XCTUnwrap(try body(NotionRequests.updateTask("p1", mapping, title: "改名", due: .some(nil)))["properties"] as? [String: Any])
        XCTAssertEqual(Set(clear.keys), ["title", "d%2Fe"])
        XCTAssertTrue((clear["d%2Fe"] as? [String: Any])?["date"] is NSNull)
        let unchanged = try XCTUnwrap(try body(NotionRequests.updateTask("p1", mapping, title: "改名"))["properties"] as? [String: Any])
        XCTAssertEqual(Set(unchanged.keys), ["title"])
        let checkbox = NotionTaskMapping(dataSourceID: "ds-2", name: "", titleProperty: "title", completion: .checkbox(property: "c"))
        let check = try XCTUnwrap(try body(NotionRequests.updateTask("p1", checkbox, completed: true))["properties"] as? [String: Any])
        XCTAssertEqual((check["c"] as? [String: Bool])?["checkbox"], true)
    }

    func testRequestsCarryVersionTokenAndJSON() throws {
        let request = NotionRequests.search(.dataSource, query: "  タスク ").urlRequest(baseURL: URL(string: "http://127.0.0.1:9/")!, token: "secret")
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:9/v1/search")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), NotionAPI.version)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(json["query"] as? String, "タスク")
        XCTAssertEqual((json["filter"] as? [String: String])?["value"], "data_source")
        XCTAssertNil(try body(NotionRequests.search(.page, query: " "))["query"])
        XCTAssertNil(NotionRequests.me().body)
        let database = try body(NotionRequests.createTaskDatabase(parentPage: "page-1", title: "Scrimのタスク"))
        let schema = try XCTUnwrap((database["initial_data_source"] as? [String: Any])?["properties"] as? [String: Any])
        XCTAssertEqual(Set(schema.keys), [NotionTaskDatabase.titleName, NotionTaskDatabase.doneName, NotionTaskDatabase.dueName])
        XCTAssertEqual((database["parent"] as? [String: String])?["page_id"], "page-1")
    }

    func testParsesSchemaTasksSearchAndErrors() throws {
        let schemaJSON = Data("""
        {"object":"data_source","id":"ds-1","title":[{"plain_text":"プロ"},{"plain_text":"ジェクト"}],
         "properties":{"名前":{"id":"title","name":"名前","type":"title","title":{}},
           "ステータス":{"id":"%3AUPp","name":"ステータス","type":"status","status":{
             "options":[{"id":"o1","name":"未着手","color":"default"},{"id":"o3","name":"完了","color":"green"}],
             "groups":[{"id":"g1","name":"To-do","option_ids":["o1"]},{"id":"g3","name":"Complete","option_ids":["o3"]}]}},
           "期限":{"id":"d%2Fe","name":"期限","type":"date","date":{}},
           "担当":{"id":"p","name":"担当","type":"people","people":{}}}}
        """.utf8)
        let schema = try NotionResponses.dataSource(schemaJSON)
        XCTAssertEqual(schema.title, "プロジェクト")
        XCTAssertEqual(schema.properties.first?.kind, .title)
        XCTAssertEqual(schema.property("%3AUPp")?.groups.last?.optionIDs, ["o3"])
        XCTAssertEqual(schema.property("p")?.kind, .people)
        let mapping = try XCTUnwrap(schema.defaultMapping())

        let tasksJSON = Data("""
        {"object":"list","has_more":true,"next_cursor":"c2","results":[
          {"object":"page","id":"p1","url":"https://app.notion.com/p/p1","created_time":"2026-11-01T00:00:00.000Z","in_trash":false,
           "properties":{"名前":{"id":"title","type":"title","title":[{"plain_text":"資料を"},{"plain_text":"共有"}]},
             "ステータス":{"id":"%3AUPp","type":"status","status":{"id":"o1","name":"未着手"}},
             "期限":{"id":"d%2Fe","type":"date","date":{"start":"2026-11-30","end":null}}}},
          {"object":"page","id":"p2","in_trash":true,"properties":{}},
          {"object":"page","id":"p4","is_archived":true,"properties":{}},
          {"object":"page","id":"p3","created_time":"2026-11-02T00:00:00.000Z",
           "properties":{"名前":{"id":"title","type":"title","title":[]},"期限":{"id":"d%2Fe","type":"date","date":null}}}]}
        """.utf8)
        let tasks = try NotionResponses.tasks(tasksJSON, mapping: mapping)
        XCTAssertEqual(tasks.map(\.id), ["p1", "p3"])
        XCTAssertEqual(tasks[0].title, "資料を共有")
        XCTAssertEqual(tasks[0].due, NotionDate(start: "2026-11-30"))
        XCTAssertEqual(tasks[0].statusOptionID, "o1")
        XCTAssertEqual(tasks[0].url?.absoluteString, "https://app.notion.com/p/p1")
        XCTAssertNil(tasks[1].due)
        XCTAssertEqual(NotionResponses.cursor(tasksJSON), "c2")
        XCTAssertNil(NotionResponses.cursor(Data(#"{"has_more":false,"next_cursor":"x"}"#.utf8)))

        let search = try NotionResponses.search(Data("""
        {"results":[{"object":"data_source","id":"a","title":[{"plain_text":"タスク"}]},
          {"object":"page","id":"b","properties":{"title":{"type":"title","title":[{"plain_text":"作業メモ"}]}}},
          {"object":"page","id":"c","in_trash":true,"properties":{}},{"object":"database","id":"d"}]}
        """.utf8))
        XCTAssertEqual(search, [NotionSearchResult(id: "a", title: "タスク", kind: .dataSource), NotionSearchResult(id: "b", title: "作業メモ", kind: .page)])
        XCTAssertEqual(try NotionResponses.createdDataSourceID(Data(#"{"object":"database","id":"db","data_sources":[{"id":"ds-new","name":"x"}]}"#.utf8)), "ds-new")
        XCTAssertThrowsError(try NotionResponses.dataSource(Data("[]".utf8)))

        let notFound = NotionResponses.error(status: 404, data: Data(#"{"object":"error","status":404,"code":"object_not_found"}"#.utf8))
        XCTAssertEqual(notFound.code, "object_not_found")
        XCTAssertTrue(notFound.message.contains("接続"))
        let limited = NotionResponses.error(status: 429, data: Data(#"{"code":"rate_limited"}"#.utf8), retryAfter: "3")
        XCTAssertTrue(limited.isRetryable)
        XCTAssertEqual(limited.retryAfter, 3)
        XCTAssertTrue(NotionResponses.error(status: 400, data: Data(#"{"code":"validation_error"}"#.utf8)).needsMapping)
        XCTAssertEqual(NotionResponses.error(status: 502, data: Data("<html>".utf8)).code, "http_502")
        XCTAssertFalse(NotionAPIError(status: 401, code: "unauthorized").isRetryable)
    }

    func testDueOrderingAndOverdue() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let tasks = [NotionTask(id: "a", title: "", createdTime: "1"),
                     NotionTask(id: "b", title: "", due: NotionDate(start: "2026-11-30"), createdTime: "2"),
                     NotionTask(id: "c", title: "", due: NotionDate(start: "2026-11-25T09:00:00+09:00"), createdTime: "3"),
                     NotionTask(id: "d", title: "", createdTime: "0")]
        XCTAssertEqual(NotionTask.ordered(tasks, calendar: calendar).map(\.id), ["c", "b", "d", "a"])
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 12))!
        XCTAssertFalse(NotionDate(start: "2026-11-25").isOverdue(now: now, calendar: calendar))
        XCTAssertTrue(NotionDate(start: "2026-11-24").isOverdue(now: now, calendar: calendar))
        XCTAssertTrue(NotionDate(start: "2026-11-25T09:00:00+09:00").isOverdue(now: now, calendar: calendar))
        XCTAssertFalse(NotionDate(start: "2026-11-25T13:00:00.000+09:00").isOverdue(now: now, calendar: calendar))
        XCTAssertEqual(NotionDate(day: now, calendar: calendar).start, "2026-11-25")
        XCTAssertFalse(NotionDate(start: "nonsense").isOverdue(now: now, calendar: calendar))
    }

    func testLinksAndIDsResolveToObjectIDs() {
        let id = "1f2e3d4c-5b6a-7988-1f2e-3d4c5b6a7988"
        for text in ["https://www.notion.so/acme/Tasks-1f2e3d4c5b6a79881f2e3d4c5b6a7988?v=0123456789abcdef0123456789abcdef",
                     "https://www.notion.so/1f2e3d4c5b6a79881f2e3d4c5b6a7988",
                     "https://app.notion.com/p/1f2e3d4c5b6a79881f2e3d4c5b6a7988",
                     "https://acme.notion.site/Tasks-1f2e3d4c5b6a79881f2e3d4c5b6a7988",
                     "notion://www.notion.so/acme/Tasks-1f2e3d4c5b6a79881f2e3d4c5b6a7988",
                     "https://www.notion.so/acme/Tasks-1f2e3d4c5b6a79881f2e3d4c5b6a7988?p=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&pm=s",
                     "  1F2E3D4C5B6A79881F2E3D4C5B6A7988 ", id] {
            XCTAssertEqual(NotionLink.objectID(from: text), id, text)
        }
        for text in ["https://example.com/Tasks-1f2e3d4c5b6a79881f2e3d4c5b6a7988", "https://calendar.notion.com/1f2e3d4c5b6a79881f2e3d4c5b6a7988",
                     "https://www.notion.so/acme/Tasks", "hello", "1f2e3d4c5b6a79881f2e3d4c5b6a798", "1f2e3d4c-5b6a79881f2e3d4c5b6a7988",
                     "https://user@www.notion.so/1f2e3d4c5b6a79881f2e3d4c5b6a7988"] {
            XCTAssertNil(NotionLink.objectID(from: text), text)
        }
    }

    func testDatabaseResponseListsDataSources() throws {
        let data = Data(#"{"object":"database","id":"db","title":[{"plain_text":"まとめ"}],"data_sources":[{"id":"a","name":"進行中"},{"id":"b","name":""}]}"#.utf8)
        XCTAssertEqual(try NotionResponses.databaseSources(data),
                       [NotionSearchResult(id: "a", title: "進行中", kind: .dataSource), NotionSearchResult(id: "b", title: "まとめ", kind: .dataSource)])
        XCTAssertEqual(NotionRequests.database("x").path, "v1/databases/x")
        XCTAssertThrowsError(try NotionResponses.databaseSources(Data("{}".utf8)))
    }

    func testFiltersCombineDueTextChoicesAndPeople() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!; calendar.firstWeekday = 2
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 12))!  // Wednesday
        let tasks = [
            NotionTask(id: "a", title: "見積もりを確認", due: NotionDate(start: "2026-11-24"), choices: ["tg": [NotionChoice(id: "t1", name: "営業")], "pp": [NotionChoice(id: "u1", name: "佐藤")]]),
            NotionTask(id: "b", title: "資料をまとめる", due: NotionDate(start: "2026-11-25"), choices: ["tg": [NotionChoice(id: "t2", name: "開発")]]),
            NotionTask(id: "c", title: "週次 Report", due: NotionDate(start: "2026-11-29"), choices: ["tg": [NotionChoice(id: "t1", name: "営業"), NotionChoice(id: "t2", name: "開発")]]),
            NotionTask(id: "d", title: "来週の準備", due: NotionDate(start: "2026-11-30")),
            NotionTask(id: "e", title: "いつか", choices: ["pp": [NotionChoice(id: "u2", name: "鈴木")]]),
        ]
        func ids(_ filter: NotionTaskFilter, text: String = "", assignee: String? = "pp") -> [String] {
            tasks.filter { filter.matches($0, text: text, assigneeProperty: assignee, now: now, calendar: calendar) }.map(\.id)
        }
        XCTAssertEqual(ids(NotionTaskFilter()), ["a", "b", "c", "d", "e"])
        XCTAssertEqual(ids(NotionTaskFilter(due: .overdue)), ["a"])
        XCTAssertEqual(ids(NotionTaskFilter(due: .today)), ["a", "b"])
        XCTAssertEqual(ids(NotionTaskFilter(due: .week)), ["a", "b", "c"])
        XCTAssertEqual(ids(NotionTaskFilter(due: .none)), ["e"])
        XCTAssertEqual(ids(NotionTaskFilter(), text: "report"), ["c"])
        XCTAssertEqual(ids(NotionTaskFilter(), text: "ＲＥＰＯＲＴ"), ["c"])
        XCTAssertEqual(ids(NotionTaskFilter(choiceProperty: "tg", choiceValues: ["t2"])), ["b", "c"])
        XCTAssertEqual(ids(NotionTaskFilter(due: .week, choiceProperty: "tg", choiceValues: ["t1"])), ["a", "c"])
        XCTAssertEqual(ids(NotionTaskFilter(people: ["u1", "u2"])), ["a", "e"])
        XCTAssertEqual(ids(NotionTaskFilter(people: ["u1"]), assignee: nil), [])
        XCTAssertFalse(NotionTaskFilter(choiceProperty: "tg").isActive)
        XCTAssertTrue(NotionTaskFilter(people: ["u1"]).isActive)
    }

    func testFiltersAndAssigneeSurviveThePanelURL() {
        let mapping = NotionTaskMapping(dataSourceID: "ds", name: "", titleProperty: "title", completion: .checkbox(property: "c"),
                                        dueProperty: "d", assigneeProperty: "p%3A1")
        let filter = NotionTaskFilter(due: .week, choiceProperty: "tg", choiceValues: ["t2", "t1"], people: ["u1"])
        let spec = WidgetSpec(kind: .notionTasks, notionTasks: mapping, notionFilter: filter)
        let restored = WidgetSpec(url: spec.url)
        XCTAssertEqual(restored?.notionTasks, mapping)
        XCTAssertEqual(restored?.notionFilter, filter)
        XCTAssertEqual(WidgetSpec(url: WidgetSpec(kind: .notionTasks, notionTasks: mapping).url)?.notionFilter, NotionTaskFilter())
        XCTAssertEqual(WidgetSpec(kind: .clock, notionFilter: filter).notionFilter, NotionTaskFilter())
    }

    func testReadsSelectMultiSelectAndPeople() throws {
        let schema = try NotionResponses.dataSource(Data("""
        {"id":"ds","title":[],"properties":{
          "名前":{"id":"title","type":"title","title":{}},
          "優先度":{"id":"pr","type":"select","select":{"options":[{"id":"h","name":"高"}]}},
          "タグ":{"id":"tg","type":"multi_select","multi_select":{"options":[{"id":"t1","name":"営業"}]}},
          "担当":{"id":"pp","type":"people","people":{}},
          "完了":{"id":"c","type":"checkbox","checkbox":{}}}}
        """.utf8))
        XCTAssertEqual(schema.choiceProperties.map(\.id).sorted(), ["pr", "tg"])
        XCTAssertEqual(schema.peopleProperties.map(\.id), ["pp"])
        XCTAssertEqual(schema.defaultMapping()?.assigneeProperty, "pp")
        var mapping = try XCTUnwrap(schema.defaultMapping())
        mapping.assigneeProperty = "tg"
        XCTAssertNotNil(schema.mappingProblem(mapping))
        let tasks = try NotionResponses.tasks(Data("""
        {"results":[{"object":"page","id":"p","properties":{
          "名前":{"id":"title","type":"title","title":[{"plain_text":"x"}]},
          "優先度":{"id":"pr","type":"select","select":{"id":"h","name":"高"}},
          "タグ":{"id":"tg","type":"multi_select","multi_select":[{"id":"t1","name":"営業"},{"id":"t2","name":"開発"}]},
          "担当":{"id":"pp","type":"people","people":[{"object":"user","id":"u1","name":"佐藤"},{"object":"user","id":"u2"}]},
          "空":{"id":"em","type":"select","select":null}}}]}
        """.utf8), mapping: try XCTUnwrap(schema.defaultMapping()))
        let choices = try XCTUnwrap(tasks.first?.choices)
        XCTAssertEqual(choices["pr"], [NotionChoice(id: "h", name: "高")])
        XCTAssertEqual(choices["tg"]?.map(\.id), ["t1", "t2"])
        XCTAssertEqual(choices["pp"], [NotionChoice(id: "u1", name: "佐藤"), NotionChoice(id: "u2", name: "")])
        XCTAssertEqual(choices["em"], [])
    }

    func testParsesBlocksAndOnlyPlainTextIsEditable() throws {
        let blocks = try NotionResponses.blocks(Data("""
        {"results":[
          {"object":"block","id":"p","type":"paragraph","has_children":false,"paragraph":{"rich_text":[{"type":"text","plain_text":"平文","text":{"content":"平文","link":null},"annotations":{"bold":false}}]}},
          {"object":"block","id":"b","type":"paragraph","has_children":false,"paragraph":{"rich_text":[{"type":"text","plain_text":"太字","annotations":{"bold":true}}]}},
          {"object":"block","id":"l","type":"paragraph","has_children":false,"paragraph":{"rich_text":[{"type":"text","plain_text":"リンク","href":"https://example.com","text":{"content":"リンク","link":{"url":"https://example.com"}}}]}},
          {"object":"block","id":"m","type":"paragraph","has_children":false,"paragraph":{"rich_text":[{"type":"mention","plain_text":"@佐藤"}]}},
          {"object":"block","id":"t","type":"to_do","has_children":true,"to_do":{"rich_text":[{"type":"text","plain_text":"確認"}],"checked":true}},
          {"object":"block","id":"h","type":"heading_3","heading_3":{"rich_text":[],"is_toggleable":false}},
          {"object":"block","id":"i","type":"image","image":{"type":"file","file":{"url":"https://files.example/a.png","expiry_time":"x"}}},
          {"object":"block","id":"cp","type":"child_page","child_page":{"title":"議事録"}},
          {"object":"block","id":"cd","type":"code","code":{"rich_text":[{"type":"text","plain_text":"let x = 1"}],"language":"swift"}},
          {"object":"block","id":"u","type":"unsupported","unsupported":{"block_type":"form"}},
          {"object":"block","id":"x","in_trash":true,"type":"paragraph","paragraph":{"rich_text":[]}},
          {"object":"block","id":"partial"}]}
        """.utf8))
        XCTAssertEqual(blocks.map(\.id), ["p", "b", "l", "m", "t", "h", "i", "cp", "cd", "u"])
        XCTAssertEqual(blocks.map(\.isEditable), [true, false, false, false, true, true, false, false, true, false])
        XCTAssertEqual(blocks[2].text.first?.href, "https://example.com")
        XCTAssertTrue(blocks[4].checked && blocks[4].hasChildren && blocks[4].kind == .todo)
        XCTAssertEqual(blocks[5].kind, .heading(3))
        XCTAssertEqual(blocks[6].url?.host, "files.example")
        XCTAssertEqual(blocks[7].label, "議事録")
        XCTAssertEqual(blocks[8].label, "swift")
        XCTAssertEqual(blocks[9].kind, .other("unsupported"))
        XCTAssertEqual(blocks[9].label, "form")
        let tree = [NotionBlock(id: "a", kind: .bulleted, children: [NotionBlock(id: "a1", kind: .bulleted, text: [NotionRichText(text: "子")])])]
        XCTAssertEqual(NotionBlock.find("a1", in: tree)?.plainText, "子")
        let renamed = NotionBlock.replacing("a1", with: NotionBlock(id: "a1", kind: .bulleted, text: [NotionRichText(text: "改")]), in: tree)
        XCTAssertEqual(NotionBlock.find("a1", in: renamed)?.plainText, "改")
        XCTAssertTrue(NotionBlock.replacing("a1", with: nil, in: tree)[0].children.isEmpty)
        let parent = NotionBlock.replacing("a", with: NotionBlock(id: "a", kind: .bulleted, text: [NotionRichText(text: "親")]), in: tree)
        XCTAssertEqual(parent[0].children.map(\.id), ["a1"], "Updates without children keep the loaded ones")
    }

    func testBlockRequests() throws {
        let children = NotionRequests.blockChildren("page", cursor: "c2")
        XCTAssertEqual(children.method, "GET")
        let url = children.urlRequest(baseURL: URL(string: "http://127.0.0.1:9/")!, token: "t").url!
        XCTAssertEqual(url.path, "/v1/blocks/page/children")
        XCTAssertEqual(Set(URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { "\($0.name)=\($0.value!)" }), ["page_size=100", "start_cursor=c2"])
        let heading = NotionBlock(id: "h", kind: .heading(2))
        let update = try body(NotionRequests.updateBlockText(heading, text: "新しい見出し"))
        XCTAssertEqual(Set(update.keys), ["heading_2"])
        XCTAssertEqual(((update["heading_2"] as? [String: Any])?["rich_text"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(try body(NotionRequests.setChecked("t", true))["to_do"] as? [String: Bool], ["checked": true])
        let append = try body(NotionRequests.appendBlock(to: "page", kind: .todo, text: "追加"))
        XCTAssertEqual(append["position"] as? [String: String], ["type": "end"])
        let child = try XCTUnwrap((append["children"] as? [[String: Any]])?.first)
        XCTAssertEqual(child["type"] as? String, "to_do")
        XCTAssertEqual((child["to_do"] as? [String: Any])?["checked"] as? Bool, false)
        XCTAssertEqual(NotionRequests.deleteBlock("b").method, "DELETE")
        let long = String(repeating: "あ", count: 4500)
        let pieces = NotionRequests.richText(long)
        XCTAssertEqual(pieces.count, 3)
        XCTAssertEqual(pieces.compactMap { ($0["text"] as? [String: String])?["content"] }.joined(), long)
        XCTAssertTrue(pieces.allSatisfy { (($0["text"] as? [String: String])?["content"]?.count ?? 0) <= 2000 })
        let status = try body(NotionRequests.updateTask("p", try XCTUnwrap(statusSchema.defaultMapping()), statusOptionID: "o2"))
        XCTAssertEqual((((status["properties"] as? [String: Any])?["%3AUPp"] as? [String: Any])?["status"] as? [String: String])?["id"], "o2")
        XCTAssertEqual(NotionTextSize.allCases.map(\.task), [13, 15, 17, 20])
    }
}
