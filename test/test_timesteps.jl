module TestTimesteps

using Mimi
using Base.Test

import Mimi:
    AbstractTimestep, FixedTimestep, VariableTimestep, TimestepVector, 
    TimestepMatrix, TimestepArray, next_timestep, hasvalue, is_first, is_last, 
    gettime

Mimi.reset_compdefs()

#####################################################
#  Test basic timestep functions for Fixed Timestep #
#####################################################

t = FixedTimestep{1850, 10, 3000}(1)
@test is_first(t)
t1 = next_timestep(t)
#t2 = new_timestep(t1, 1860)
#@test is_first(t2)
#t3 = new_timestep(t2, 1840)
#@test t3.t == 3

t = FixedTimestep{2000, 1, 2050}(51)
@test is_last(t)
t = next_timestep(t)
@test_throws ErrorException next_timestep(t)

########################################################
#  Test basic timestep functions for Variable Timestep #
########################################################
years = ([2000:1:2024; 2025:5:2105]...)

t = VariableTimestep{years}()
@test is_first(t)

t = VariableTimestep{years}(42)
@test is_last(t)
@test ! is_first(t)
t = next_timestep(t)
@test_throws ErrorException next_timestep(t)

#########################################################
#  Test a model with components with different offsets  #
#########################################################

# we'll have Bar run from 2000 to 2010
# and Foo from 2005 to 2010

@defcomp Foo begin
    inputF = Parameter()
    output = Variable(index=[time])
    
    function run_timestep(p, v, d, ts::AbstractTimestep)
        v.output[ts] = p.inputF + ts.t
    end
end

@defcomp Bar begin
    inputB = Parameter(index=[time])
    output = Variable(index=[time])
    
    function run_timestep(p, v, d, ts::AbstractTimestep)      # TBD: Was ts::Timestep, but it's broken currently...
        if gettime(ts) < 2005
            v.output[ts] = p.inputB[ts]
        else
            v.output[ts] = p.inputB[ts] * ts.t
        end
    end
end

m = Model()
set_dimension!(m, :time, 2000:2010)

# test that you can only add components with first/last within model's time index range
@test_throws ErrorException addcomponent(m, Foo; first=1900)
@test_throws ErrorException addcomponent(m, Foo; last=2100)

foo = addcomponent(m, Foo; first=2005) #offset for foo
bar = addcomponent(m, Bar)

set_parameter!(m, :Foo, :inputF, 5.)
set_parameter!(m, :Bar, :inputB, collect(1:11))

run(m)

@test length(m[:Foo, :output])==6
@test length(m[:Bar, :output])==11

for i in 1:6
    @test m[:Foo, :output][i] == 5+i
end

for i in 1:5
    @test m[:Bar, :output][i] == i
end

for i in 6:11
    @test m[:Bar, :output][i] == i*i
end

##################################################
#  Now build a model with connecting components  #
##################################################

@defcomp Foo2 begin
    inputF = Parameter(index=[time])
    output = Variable(index=[time])
    
    function run_timestep(p, v, d, ts)
        v.output[ts] = p.inputF[ts]
    end
end

m2 = Model()
set_dimension!(m2, :time, 2000:2010)
bar = addcomponent(m2, Bar)
foo2 = addcomponent(m2, Foo2, first=2005) #offset for foo

set_parameter!(m2, :Bar, :inputB, collect(1:11))
connect_parameter(m2, :Foo2, :inputF, :Bar, :output)

run(m2)

for i in 1:6
    @test m2[:Foo2, :output][i] == (i+5)^2
end

#########################################
#  Connect them in the other direction  #
#########################################

@defcomp Bar2 begin
    inputB = Parameter(index=[time])
    output = Variable(index=[time])
    
    function run_timestep(p, v, d, ts::AbstractTimestep)
        if gettime(ts) < 2005
            v.output[ts] = 0
        else
            v.output[ts] = p.inputB[ts] * ts.t
        end
    end
end

m3 = Model()

set_dimension!(m3, :time, 2000:2010)
addcomponent(m3, Foo, first=2005)
addcomponent(m3, Bar2)

set_parameter!(m3, :Foo, :inputF, 5.)
connect_parameter(m3, :Bar2, :inputB, :Foo, :output)
run(m3)

@test length(m3[:Foo, :output]) == 6
@test length(m3[:Bar2, :inputB]) == 6
@test length(m3[:Bar2, :output]) == 11

end