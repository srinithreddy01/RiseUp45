const plan = {
  Monday: ['Back + Bicep', ['Back exercises', 'Bicep exercises']],
  Tuesday: ['Chest + Tricep', ['Chest exercises', 'Tricep exercises']],
  Wednesday: ['Shoulder + Forearm', ['Shoulder exercises', 'Forearm exercises']],
  Thursday: ['Core (ABS) + Bicep', ['Core exercises', 'Bicep exercises']],
  Friday: ['Legs', ['Leg exercises', 'Mobility work']],
  Saturday: ['Shoulder + ABS', ['Shoulder exercises', 'ABS exercises']],
  Sunday: ['Rest Day', []],
}
export function workoutForDate(date) { const day = date.toLocaleDateString('en-US', { weekday: 'long' }); const [name, items] = plan[day]; return { day, name, items, rest: day === 'Sunday' } }
