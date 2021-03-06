import UIKit

/// Table view data source.
///
/// You should always access this object from the main thread since it talks to UIKit.
public class DataSource: NSObject {
    
    // MARK: - Properties
    
    /// The table view that will use this object as its data source.
    public weak var tableView: UITableView? {
        willSet {
            if let tableView = tableView {
                tableView.dataSource = nil
                tableView.delegate = nil
            }
            
            registeredCellIdentifiers.removeAll()
        }
        
        didSet {
            assert(Thread.isMainThread, "You must access Static.DataSource from the main thread.")
            updateTableView()
        }
    }
    
    /// Sections to use in the table view.
    public var sections: [Section] {
        didSet {
            assert(Thread.isMainThread, "You must access Static.DataSource from the main thread.")
            refresh()
        }
    }
    
    /// Section index titles.
    public var sectionIndexTitles: [String]? {
        didSet {
            assert(Thread.isMainThread, "You must access Static.DataSource from the main thread.")
            tableView?.reloadData()
        }
    }
    
    /// Automatically deselect rows after they are selected
    public var automaticallyDeselectRows = true
    
    private var registeredCellIdentifiers = Set<String>()
    
    
    // MARK: - Initializers
    
    /// Initialize with optional `tableView` and `sections`.
    public init(tableView: UITableView? = nil, sections: [Section]? = nil) {
        assert(Thread.isMainThread, "You must access Static.DataSource from the main thread.")
        
        self.tableView = tableView
        self.sections = sections ?? []
        
        super.init()
        
        updateTableView()
    }
    
    public var reusingIsEnabled: Bool = true {
        didSet {
            tableView?.reloadData()
        }
    }
    
    public weak var scrollDelegate: UIScrollViewDelegate?
    
    public var cellConfigurator: ((UITableViewCell?, IndexPath) -> Void)?
    
    deinit {
        // nil out the table view to ensure the table view data source and delegate niled out
        tableView = nil
    }
    
    
    // MARK: - Public
    
    public func row(at point: CGPoint) -> Row? {
        guard let indexPath = tableView?.indexPathForRow(at: point) else { return nil }
        return row(at: indexPath)
    }
    
    /// Updates row at given `indexPath`
    ///
    /// - parameter indexPath:     The index path of updated row.
    /// - parameter animated:  Flag to determine way of update.
    /// - parameter updater:  Closure to update, which takes old row as parameter, returns row with updated state.
    ///
    public func updateRow(at indexPath: IndexPath,
                          animated: Bool = false,
                          updater: (Row) -> Row) {
        
        guard let row = self.row(at: indexPath) else {
            return
        }
        
        let newRow = updater(row)
        guard var section = section(at: indexPath.section) else {
            return
        }
        
        section.rows[indexPath.row] = newRow
        sections[indexPath.section] = section
        
        if !animated {
            tableView?.reloadData()
            return
        }
        
        tableView?.beginUpdates()
        tableView?.reloadRows(at: [indexPath], with: .automatic)
        tableView?.endUpdates()
    }
    
    /// Updates all rows satisfying passed condition
    ///
    /// - parameter animated:  Flag to determine way of update.
    /// - parameter filter:   Takes old row, returns flag which indicates that row should be udated or not
    /// - parameter updater:  Closure to update, which takes old row as parameter, returns row with updated state.
    ///
    
    public func updateRows(animated: Bool, filter: (Row) -> Bool, updater: (Row) -> Row) {
        for (sectionIndex, section) in sections.enumerated() {
            for (rowIndex, row) in section.rows.enumerated() {
                if filter(row) {
                    let indexPath = IndexPath(row: rowIndex, section: sectionIndex)
                    updateRow(at: indexPath, animated: animated, updater: updater)
                }
            }
        }
    }
    
    // MARK: - Private
    
    private func updateTableView() {
        guard let tableView = tableView else { return }
        tableView.dataSource = self
        tableView.delegate = self
        refresh()
    }
    
    private func refresh() {
        refreshTableSections()
        refreshRegisteredCells()
    }
    
    fileprivate func section(at index: Int) -> Section? {
        if sections.count <= index {
            assert(false, "Invalid section index: \(index)")
            return nil
        }
        
        return sections[index]
    }
    
    fileprivate func row(at indexPath: IndexPath) -> Row? {
        if let section = section(at: indexPath.section) {
            let rows = section.rows
            if rows.count >= indexPath.row {
                return rows[indexPath.row]
            }
        }
        
        assert(false, "Invalid index path: \(indexPath)")
        return nil
    }
    
    private func refreshTableSections(oldSections: [Section]? = nil) {
        guard let tableView = tableView else { return }
        guard let oldSections = oldSections else {
            tableView.reloadData()
            return
        }
        
        let oldCount = oldSections.count
        let newCount = sections.count
        let delta = newCount - oldCount
        let animation = UITableViewRowAnimation.automatic
        
        tableView.beginUpdates()
        
        if delta == 0 {
            tableView.reloadSections(IndexSet(integersIn: 0..<newCount), with: animation)
        } else {
            if delta > 0 {
                // Insert sections
                let start = oldCount - 1
                let range: Range<IndexSet.Element> = start..<(start + delta)
                tableView.insertSections(IndexSet(integersIn: range), with: animation)
            } else {
                // Remove sections
                let start = oldCount - 1
                let range: Range<IndexSet.Element> = start..<(start - delta)
                tableView.deleteSections(IndexSet(integersIn: range), with: animation)
            }
            
            // Reload existing sections
            let commonCount = min(oldCount, newCount)
            tableView.reloadSections(IndexSet(integersIn: 0..<commonCount), with: animation)
        }
        
        tableView.endUpdates()
    }
    
    private func refreshRegisteredCells() {
        // A table view is required to manipulate registered cells
        guard let tableView = tableView else { return }
        
        // Filter to only rows with unregistered cells
        let rows = sections.flatMap{ $0.rows }.filter { !self.registeredCellIdentifiers.contains($0.cellIdentifier) }
        
        for row in rows {
            let identifier = row.cellIdentifier
            
            // Check again in case there were duplicate new cell classes
            if registeredCellIdentifiers.contains(identifier) {
                continue
            }
            
            registeredCellIdentifiers.insert(identifier)
            if let nib = row.cellClass.nib() {
                tableView.register(nib, forCellReuseIdentifier: identifier)
            } else {
                tableView.register(row.cellClass, forCellReuseIdentifier: identifier)
            }
        }
    }
}


extension DataSource: UITableViewDataSource {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection sectionIndex: Int) -> Int {
        return section(at: sectionIndex)?.rows.count ?? 0
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let row = row(at: indexPath) {
            let tableCell: UITableViewCell
            if  reusingIsEnabled {
                tableCell = tableView.dequeueReusableCell(withIdentifier: row.cellIdentifier, for: indexPath)
            } else {
                tableCell = row.cellClass.instance()
            }
            
            if let cell = tableCell as? Cell {
                cell.configure(row: row)
            }
            
            cellConfigurator?(tableCell, indexPath)
            
            return tableCell
        }
        
        return UITableViewCell()
    }
    
    public func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }
    
    public func tableView(_ tableView: UITableView, titleForHeaderInSection sectionIndex: Int) -> String? {
        return section(at: sectionIndex)?.header?._title
    }
    
    public func tableView(_ tableView: UITableView, viewForHeaderInSection sectionIndex: Int) -> UIView? {
        return section(at: sectionIndex)?.header?._view
    }
    
    public func tableView(_ tableView: UITableView, heightForHeaderInSection sectionIndex: Int) -> CGFloat {
        return section(at: sectionIndex)?.header?.viewHeight ?? UITableViewAutomaticDimension
    }
    
    public func tableView(_ tableView: UITableView, titleForFooterInSection sectionIndex: Int) -> String? {
        return section(at: sectionIndex)?.footer?._title
    }
    
    public func tableView(_ tableView: UITableView, viewForFooterInSection sectionIndex: Int) -> UIView? {
        return section(at: sectionIndex)?.footer?._view
    }
    
    public func tableView(_ tableView: UITableView, heightForFooterInSection sectionIndex: Int) -> CGFloat {
        return section(at: sectionIndex)?.footer?.viewHeight ?? UITableViewAutomaticDimension
    }
    
    public func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return row(at: indexPath)?.canEdit ?? false
    }
    
    @objc(tableView:editActionsForRowAtIndexPath:)
    public func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        return row(at: indexPath)?.editActions.map {
            action in
            let rowAction = UITableViewRowAction(style: action.style, title: action.title) { (_, _) in
                action.selection?()
            }
            
            // These calls have side effects when setting to nil
            // Setting a background color to nil will wipe out any predefined style
            // Wrapping these in if-lets prevents nil-setting side effects
            if let backgroundColor = action.backgroundColor {
                rowAction.backgroundColor = backgroundColor
            }
            
            if let backgroundEffect = action.backgroundEffect {
                rowAction.backgroundEffect = backgroundEffect
            }
            
            return rowAction
        }
    }
    
    public func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        guard let sectionIndexTitles = sectionIndexTitles, sectionIndexTitles.count >= sections.count else { return nil }
        return sectionIndexTitles
    }
    
    public func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
        for (i, section) in sections.enumerated() {
            if let indexTitle = section.indexTitle, indexTitle == title {
                return i
            }
        }
        return max(index, sections.count - 1)
    }
}


extension DataSource: UITableViewDelegate {
    public func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return row(at: indexPath)?.isSelectable ?? false
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if automaticallyDeselectRows {
            tableView.deselectRow(at: indexPath as IndexPath, animated: true)
        }
        
        if let row = row(at: indexPath) {
            row.selection?()
        }
    }
    
    public func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        if let row = row(at: indexPath) {
            row.accessory.selection?()
        }
    }
    
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if let row = row(at: indexPath) {
            return row.height()
        }
        return tableView.rowHeight
        
    }
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        scrollDelegate?.scrollViewDidScroll?(scrollView)
    }
    
    public func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
       scrollDelegate?.scrollViewWillEndDragging?(scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset)
    }
    
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        scrollDelegate?.scrollViewWillBeginDragging?(scrollView)
    }
    
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scrollDelegate?.scrollViewDidEndDecelerating?(scrollView)
    }


}
