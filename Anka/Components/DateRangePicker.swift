import SwiftUI

struct DateRangePicker: View {
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    
    // Internal state for which month is currently visible
    @State private var displayedMonth: Date = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(spacing: 24) {
            header
                .padding(.top, 16)
            
            // Weekday Headers
            HStack(spacing: 0) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                    Text(day)
                        .font(.dsCaptionMedium)
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            
            MonthGrid(
                monthDate: displayedMonth,
                startDate: $startDate,
                endDate: $endDate,
                calendar: calendar
            )
            .padding(.horizontal)
            
            Spacer()
        }
        .padding(.top, 24)
        .onAppear {
            if let start = startDate {
                displayedMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? displayedMonth
            }
        }
    }
    
    private var header: some View {
        HStack {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.dsBodySemi)
                    .foregroundStyle(DSColor.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(DSColor.bgSecondary, in: Circle())
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            VStack(spacing: 2) {
                Text(monthName)
                    .font(.dsHeadlineSemi)
                    .foregroundStyle(DSColor.textPrimary)
                
                Text(subtitleText)
                    .font(.dsCaptionMedium)
                    .foregroundStyle(DSColor.textSecondary)
            }
            
            Spacer()
            
            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.dsBodySemi)
                    .foregroundStyle(DSColor.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(DSColor.bgSecondary, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }
    
    private var subtitleText: String {
        if startDate != nil && endDate != nil {
            return "Range Selected"
        } else if startDate != nil {
            return "Select End Date"
        } else {
            return "Select Start Date"
        }
    }
    
    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }
    
    private func changeMonth(by value: Int) {
        if let newDate = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            withAnimation(.easeInOut(duration: 0.2)) {
                displayedMonth = newDate
            }
        }
    }
}

// MARK: - Month Grid

private struct MonthGrid: View {
    let monthDate: Date
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    let calendar: Calendar
    
    let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    
    private var days: [Date?] {
        let range = calendar.range(of: .day, in: .month, for: monthDate)!
        let firstWeekday = calendar.component(.weekday, from: monthDate)
        
        var generatedDays: [Date?] = []
        // Add nil padding for days before the 1st
        for _ in 0..<(firstWeekday - 1) {
            generatedDays.append(nil)
        }
        
        // Add actual dates
        for dayOffset in 0..<range.count {
            if let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: monthDate) {
                generatedDays.append(dayDate)
            }
        }
        return generatedDays
    }
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            let currentDays = days
            ForEach(0..<currentDays.count, id: \.self) { index in
                if let date = currentDays[index] {
                    DayCell(
                        date: date,
                        startDate: $startDate,
                        endDate: $endDate,
                        calendar: calendar
                    )
                } else {
                    Color.clear
                        .frame(height: 44)
                }
            }
        }
    }
}

// MARK: - Day Cell

private struct DayCell: View {
    let date: Date
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    let calendar: Calendar
    
    var isToday: Bool {
        calendar.isDateInToday(date)
    }
    
    var isStartDate: Bool {
        guard let start = startDate else { return false }
        return calendar.isDate(date, inSameDayAs: start)
    }
    
    var isEndDate: Bool {
        guard let end = endDate else { return false }
        return calendar.isDate(date, inSameDayAs: end)
    }
    
    var isBetween: Bool {
        guard let start = startDate, let end = endDate else { return false }
        return date > start && date < end
    }
    
    var body: some View {
        Text("\(calendar.component(.day, from: date))")
            .font(isStartDate || isEndDate ? .dsBodySemi : .dsBodyMedium)
            .foregroundStyle(isStartDate || isEndDate ? DSColor.textOnAccent : DSColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                backgroundShape
            }
            .contentShape(Rectangle())
            .onTapGesture {
                handleTap()
            }
    }
    
    @ViewBuilder
    private var backgroundShape: some View {
        GeometryReader { geo in
            ZStack {
                // Background highlight spanning the full width (height locked to 40 to hug the circle)
                if isBetween {
                    DSColor.accentSoft
                        .frame(width: geo.size.width, height: 40)
                } else if isStartDate && endDate != nil {
                    // Start date: extend highlight exactly to the right edge
                    DSColor.accentSoft
                        .frame(width: geo.size.width / 2, height: 40)
                        .offset(x: geo.size.width / 4)
                } else if isEndDate && startDate != nil {
                    // End date: extend highlight exactly to the left edge
                    DSColor.accentSoft
                        .frame(width: geo.size.width / 2, height: 40)
                        .offset(x: -geo.size.width / 4)
                }
                
                // Solid circle for selection
                if isStartDate || isEndDate {
                    Circle()
                        .fill(DSColor.accent)
                        .frame(width: 40, height: 40)
                        .shadow(color: DSColor.accent.opacity(0.3), radius: 4, y: 2)
                } else if isToday && !isBetween {
                    // Today indicator when not selected
                    Circle()
                        .strokeBorder(DSColor.accentSoft, lineWidth: 1.5)
                        .frame(width: 40, height: 40)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }
    
    private func handleTap() {
        let normalizedDate = calendar.startOfDay(for: date)
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.prepare()
        impact.impactOccurred()
        
        withAnimation(.easeInOut(duration: 0.2)) {
            if let start = startDate {
                if endDate != nil {
                    // Both selected -> reset to new start date
                    startDate = normalizedDate
                    endDate = nil
                } else {
                    // Only start selected
                    if normalizedDate < start {
                        startDate = normalizedDate
                    } else if normalizedDate > start {
                        // End date is inclusive
                        endDate = normalizedDate
                    } else {
                        // Tapped start date again -> clear selection
                        startDate = nil
                    }
                }
            } else {
                // Nothing selected
                startDate = normalizedDate
            }
        }
    }
}
