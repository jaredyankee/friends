# Friends
Friends is a mobile app designed to coordinate plans with your friends. Users can import their work schedules to populate a calendar that is then sharable with other users, or groups of users

The intention behind the app is to create an easy way for individuals or groups of people to plan meet-ups and events at a time that works for everyone. It will find the best time for you to connect.

## Proposed Data Structure

- Accounts, ("Friends") have a schedule. They can add items to their schedule to block off time, marking them as unavailable.
    - items in their schedule can be set to public, or private on the basis of groups or individuals. Events can also be ambiguous (Blanket "unavailable") or transparent ("I am at work from 9am - 5pm").
- Groups of friends can be created. The group will have a full calendar that is a composite of all group members schedules.Clicking a timeblock in the groups schedule will show who is available at that time. 
    - Users can filter group availability by person
    - Times when all friends/group members are available are highlighted
- Groups should also have messaging capability

## Features
- Upload a picture of your work schedule to auto-populate your calendar for work
- color code your availability for different types of events (public or private)
- Set cadence for recurring scheduled items.

## Tech
This would be best suited as a mobile app. Focus on development for iOS first. 

## Development
All development for this app will be done through Claude Code. Claude Code should make pull requests to the repository as if it were a developer working on the project. The owner of the repository will provide feedback and guidance along with the PR

## Style
Customizable color themes with light and dark mode. 
- Simple design with 1 primary color, a couple of shades of it, and then white text on that color (or inverse for dark mode)
