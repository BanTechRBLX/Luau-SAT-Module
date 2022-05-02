--!strict

local UNIQUENESS_DOT_THRESHOLD = 0.999

export type Point = { Type: string, Position: Vector2 }
export type Circle = { Type: string, Position: Vector2, Radius: number }
export type Polygon = { Type: string, Vertices: { Vector2 } }

local function enforceType( object: any )
    if object.Type == "point" then
        object = object :: Point
        assert( typeof( object.Position ) == "Vector2", "Position invalid. Should be a Vector2." )
    elseif object.Type == "circle" then
        object = object :: Circle
        assert( typeof( object.Position ) == "Vector2", "Position invalid. Should be a Vector2." )
        assert( typeof( object.Radius ) == "number", "Radius invalid. Should be a number." )
    elseif object.Type == "polygon" then
        object = object :: Polygon
        assert( typeof( object.Vertices ) == "table", "Vertices invalid. Should be an array." )
        local array = {}
        for _, vertex in ipairs( object.Vertices ) do
            assert(
                typeof( vertex ) == "Vector2",
                "Vertices contains invalid elements. Should be an array of Vector2 elements."
            )
            table.insert( array, vertex )
        end
        assert( #array >= 3, "Polygon invalid. Should contain at least 3 vertices." )
        object.Vertices = array
    else
        error( "Object invalid." )
    end
    return object
end

local function findCentroidFromVertices( vertices: { Vector2 } ): Vector2
    local x = 0
    local y = 0

    for _, vertex in ipairs( vertices ) do
        x += vertex.X
        y += vertex.Y
    end

    local vertexCount = #vertices
    return Vector2.new( x / vertexCount, y / vertexCount )
end

local function sortPolygonVertices( vertices: { Vector2 } ): { Vector2 }
    local twoPi = math.pi * 2
    local centroid = findCentroidFromVertices( vertices )

    table.sort( vertices, function ( vertexA: Vector2, vertexB: Vector2 )
        local a1 = ( math.atan2(vertexA.X - centroid.X, vertexA.Y - centroid.Y) + twoPi ) % twoPi
        local a2 = ( math.atan2(vertexB.X - centroid.X, vertexB.Y - centroid.Y) + twoPi ) % twoPi
        return a1 < a2
    end )

    return vertices
end

local function getPolygonNormals( polygon: Polygon ): { Vector2 }
    local normals = {}
    local vertexCount = #polygon.Vertices
    for side = 1, vertexCount do
        local vertexA = polygon.Vertices[ side ]
        local vertexB = polygon.Vertices[ ( side % vertexCount ) + 1 ]
        local vector = vertexB - vertexA
        table.insert( normals, Vector2.new( vector.Y, -vector.X ).Unit )
    end
    return normals
end

local function filterUniqueNormals( normals: { Vector2 } ) : { Vector2 }
    local uniqueNormals = {}
    for index, normal in ipairs( normals ) do
        if index > 1 then
            local duplicate = false
            for i = 1, index - 1 do
                local dot = normal:Dot( normals[ i ] )
                if dot >= UNIQUENESS_DOT_THRESHOLD or dot <= -UNIQUENESS_DOT_THRESHOLD then
                    duplicate = true
                    break
                end
            end
            if duplicate then
                continue
            end
        end
        table.insert( uniqueNormals, normal )
    end
    return uniqueNormals
end

local function projectVertices( vertices: { Vector2 }, axis: Vector2 ): ( number, number )
    local minimum: number, maximum: number

    for _, vertex in ipairs( vertices ) do
        local projection = vertex:Dot( axis )
        if not minimum or projection < minimum then
            minimum = projection
        end
        if not maximum or projection > maximum then
            maximum = projection
        end
    end

    return minimum, maximum
end

local function projectObject( object: any, axis: Vector2 ): ( number, number, number? )
    local vertices
    if object.Type == "polygon" then
        vertices = object.Vertices
    elseif object.Type == "circle" or object.Type == "point" then
        vertices = { object.Position }
    end
    local min, max = projectVertices( vertices, axis )
    local circleMid
    if object.Type == "circle" then
        circleMid = min
        min -= object.Radius
        max += object.Radius
    end
    return min, max, circleMid
end

local function checkNumberBetweenNumbers( num: number, min: number, max: number ): boolean
    return num >= min and num <= max
end

local function checkForOverlap( minA: number, maxA: number, minB: number, maxB: number ): boolean
    local check1 = checkNumberBetweenNumbers( minA, minB, maxB )
    local check2 = checkNumberBetweenNumbers( maxA, minB, maxB )
    local check3 = checkNumberBetweenNumbers( minB, minA, maxA )
    local check4 = checkNumberBetweenNumbers( maxB, minA, maxA )

    return check1 or check2 or check3 or check4
end

local SatCollision = {}

function SatCollision.CreatePoint( position: Vector2 ): Point
    assert( position, "Argument 1 (Position) missing." )
    assert( typeof( position ) == "Vector2", "Argument 1 (Position) invalid. Should be a Vector2." )

    local point: Point = { Type = "point", Position = position }
    return point
end

function SatCollision.CreateCircle( position: Vector2, radius: number ): Circle
    assert( position, "Argument 1 (Position) missing." )
    assert( typeof( position ) == "Vector2", "Argument 1 (Position) invalid. Should be a Vector2." )
    assert( radius, "Argument 2 (Radius) missing." )
    assert(
        typeof( radius ) == "number" and radius > 0,
        "Argument 2 (Radius) invalid. Should be a positive number."
    )

    local circle: Circle = { Type = "circle", Position = position, Radius = radius }
    return circle
end

function SatCollision.CreatePolygon( vertices: { Vector2 } ): Polygon
    assert( vertices, "Argument 1 (Vertices) missing." )
    local array = {}
    for _, vertex in ipairs( vertices ) do
        assert(
            typeof( vertex ) == "Vector2",
            "Argument 1 (Vertices) contains invalid elements."
                .. "Should be an array of Vector2 elements."
        )
        table.insert( array, vertex )
    end
    assert( #array >= 3, "Argument 1 (Vertices) invalid. Should contain at least 3 vertices." )
    vertices = sortPolygonVertices( array )

    local polygon: Polygon = { Type = "polygon", Vertices = vertices }
    return polygon
end

function SatCollision.RotatePolygon( polygon: Polygon, radians: number, centre: Vector2 ): Polygon
    assert( polygon, "Argument 1 (Polygon) missing." )
    assert( typeof( polygon ) == "table", "Argument 1 (Polygon) invalid. Should be a table." )
    assert( polygon.Type == "polygon", "Argument 1 (Polygon) invalid." )
    assert( radians, "Argument 2 (Radians) missing." )
    assert( typeof( radians ) == "number", "Argument 2 (Radians) invalid. Should be a number." )
    assert( centre, "Argument 3 (Centre) missing." )
    assert( typeof( centre ) == "Vector2", "Argument 3 (Centre) invalid. Should be a Vector2." )

    polygon = enforceType( polygon )

    local sin, cos = math.sin( radians ), math.cos( radians )
    for index, vertex in ipairs( polygon.Vertices ) do
        local x, y = vertex.X - centre.X, vertex.Y - centre.Y
        polygon.Vertices[ index ] = Vector2.new( x * cos - y * sin, x * sin + y * cos ) + centre
    end
    return polygon
end

function SatCollision.AreObjectsColliding( objectA: any, objectB: any ): boolean
    assert( objectA, "Argument 1 (Object A) missing." )
    assert( typeof( objectA ) == "table", "Argument 1 (Object A) invalid. Should be a table." )
    assert( objectB, "Argument 2 (Object B) missing." )
    assert( typeof( objectB ) == "table", "Argument 2 (Object B) invalid. Should be a table." )

    objectA = enforceType( objectA )
    objectB = enforceType( objectB )

    -- A) Point to Point collision
    if objectA.Type == "point" and objectB.Type == "point" then
        return objectA.Position == objectB.Position
    end

    -- B) Circle to Circle collision
    if objectA.Type == "circle" and objectB.Type == "circle" then
        return ( objectA.Position - objectB.Position ).Magnitude <= objectA.Radius + objectB.Radius
    end

    -- C) Circle to Point collision
    if ( objectA.Type == "circle" or objectB.Type == "circle" )
        and ( objectA.Type == "point" or objectB.Type == "point" )
    then
        local point = objectA.Type == "point" and objectA or objectB
        local circle = objectA.Type == "circle" and objectA or objectB

        return ( point.Position - circle.Position ).Magnitude <= circle.Radius
    end

    -- D) All other combinations
    local axes = {}
    -- Object A
    if objectA.Type == "polygon" then
        local normals = getPolygonNormals( objectA )
        for _, normal in ipairs( normals ) do
            table.insert( axes, normal )
        end
    end
    -- Object B
    if objectB.Type == "polygon" then
        local normals = getPolygonNormals( objectB )
        for _, normal in ipairs( normals ) do
            table.insert( axes, normal )
        end
    end
    -- Filter unique normals
    axes = filterUniqueNormals( axes )

    local circleOverlapped: boolean = false
    for _, axis in ipairs( axes ) do
        -- Project A
        local minA, maxA, circleA = projectObject( objectA, axis )

        -- Project B
        local minB, maxB, circleB = projectObject( objectB, axis )

        -- Check for overlap
        local isOverlapped: boolean = checkForOverlap( minA, maxA, minB, maxB )
        if not isOverlapped then
            return false
        end

        if circleA or circleB then
            local min, max, circle, vertices, centre, radius
            if circleA then
                min = minB
                max = maxB
                circle = circleA
                vertices = objectB.Vertices
                centre = objectA.Position
                radius = objectA.Radius
            else
                min = minA
                max = maxA
                circle = circleB
                vertices = objectA.Vertices
                centre = objectB.Position
                radius = objectB.Radius
            end

            local centreOverlap: boolean = circle >= min and circle <= max
            if centreOverlap then
                circleOverlapped = true
            elseif not circleOverlapped then
                for _, vertex in ipairs( vertices ) do
                    if ( vertex - centre ).Magnitude <= radius then
                        circleOverlapped = true
                    end
                end
            end
        end
    end

    if not circleOverlapped and ( objectA.Type == "circle" or objectB.Type == "circle" ) then
        return false
    end
    return true
end

return SatCollision
